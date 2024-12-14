import { Static } from "@sinclair/typebox";
import {
  schemaValidate,
  schemaValidateWithErr,
} from "isomorphic-lib/src/resultHandling/schemaValidation";

import logger from "./logger";
import prisma from "./prisma";
import {
  FeatureConfigByType,
  FeatureMap,
  FeatureNames,
  FeatureNamesEnum,
  Features,
} from "./types";
import {
  startComputePropertiesWorkflow,
  terminateComputePropertiesWorkflow,
} from "./computedProperties/computePropertiesWorkflow/lifecycle";

export async function getFeature({
  name,
  workspaceId,
}: {
  workspaceId: string;
  name: FeatureNamesEnum;
}): Promise<boolean> {
  const feature = await prisma().feature.findUnique({
    where: {
      workspaceId_name: {
        workspaceId,
        name,
      },
    },
  });
  return feature?.enabled ?? false;
}

export async function getFeatureConfig<T extends FeatureNamesEnum>({
  name,
  workspaceId,
}: {
  workspaceId: string;
  name: T;
}): Promise<Static<(typeof FeatureConfigByType)[T]> | null> {
  const feature = await prisma().feature.findUnique({
    where: {
      workspaceId_name: {
        workspaceId,
        name,
      },
    },
  });
  if (!feature?.enabled) {
    return null;
  }
  const validated = schemaValidateWithErr(
    feature.config,
    FeatureConfigByType[name],
  );
  if (validated.isErr()) {
    logger().error(
      {
        err: validated.error,
        workspaceId,
        name,
        feature,
      },
      "Feature config is not valid",
    );
    return null;
  }
  return validated.value;
}

export async function getFeatures({
  names,
  workspaceId,
}: {
  workspaceId: string;
  names?: FeatureNamesEnum[];
}): Promise<FeatureMap> {
  const features = await prisma().feature.findMany({
    where: {
      workspaceId,
      ...(names ? { name: { in: names } } : {}),
    },
  });
  return features.reduce<FeatureMap>((acc, feature) => {
    const validated = schemaValidate(feature.name, FeatureNames);
    if (validated.isErr()) {
      return acc;
    }
    if (!feature.enabled) {
      acc[validated.value] = false;
      return acc;
    }
    if (feature.config && typeof feature.config === "object") {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      acc[validated.value] = feature.config;
      return acc;
    }
    acc[validated.value] = feature.enabled;
    return acc;
  }, {});
}

export async function addFeatures({
  workspaceId,
  features,
}: {
  workspaceId: string;
  features: Features;
}) {
  await Promise.all(
    features.map((feature) =>
      prisma().feature.upsert({
        where: {
          workspaceId_name: {
            workspaceId,
            name: feature.type,
          },
        },
        create: {
          workspaceId,
          name: feature.type,
          enabled: true,
          config: feature,
        },
        update: {
          enabled: true,
          config: feature,
        },
      }),
    ),
  );

  const effects = features.flatMap((feature) => {
    switch (feature.type) {
      case FeatureNamesEnum.ComputePropertiesGlobal:
        return terminateComputePropertiesWorkflow({ workspaceId });
      default:
        return [];
    }
  });
  await Promise.all(effects);
}

export async function removeFeatures({
  workspaceId,
  names,
}: {
  workspaceId: string;
  names: FeatureNamesEnum[];
}) {
  await prisma().feature.deleteMany({
    where: {
      workspaceId,
      name: { in: names },
    },
  });

  const effects = names.flatMap((name) => {
    switch (name) {
      case FeatureNamesEnum.ComputePropertiesGlobal:
        return startComputePropertiesWorkflow({ workspaceId });
      default:
        return [];
    }
  });
  await Promise.all(effects);
}
