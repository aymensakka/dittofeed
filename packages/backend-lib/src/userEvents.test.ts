import { Workspace } from "@prisma/client";
import { randomUUID } from "crypto";

import { segmentIdentifyEvent } from "../test/factories/segment";
import config from "./config";
import prisma from "./prisma";
import { findAllUserTraits } from "./userEvents";
import { insertUserEvents } from "./userEvents/clickhouse";

describe("findAllUserTraits", () => {
  let workspace: Workspace;
  beforeEach(async () => {
    workspace = await prisma.workspace.create({
      data: { name: `workspace-${randomUUID()}` },
    });
    await insertUserEvents({
      tableVersion: config().defaultUserEventsTableVersion,
      workspaceId: workspace.id,
      events: [
        {
          messageId: randomUUID(),
          messageRaw: segmentIdentifyEvent({
            traits: {
              status: "onboarding",
              name: "max",
            },
          }),
        },
        {
          messageId: randomUUID(),
          messageRaw: segmentIdentifyEvent({
            traits: {
              status: "onboarding",
              height: "73",
            },
          }),
        },
      ],
    });
  });

  it("returns the relevant traits without duplicates", async () => {
    const userTraits = await findAllUserTraits({
      workspaceId: workspace.id,
      tableVersion: config().defaultUserEventsTableVersion,
    });
    userTraits.sort();
    expect(userTraits).toEqual(["height", "name", "status"]);
  });
});
