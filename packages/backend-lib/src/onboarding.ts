import { eq, and } from "drizzle-orm";
import { unwrap } from "isomorphic-lib/src/resultHandling/resultUtils";
import { err, ok, Result } from "neverthrow";

import { db, insert } from "./db";
import {
  workspace as dbWorkspace,
  workspaceMember as dbWorkspaceMember,
  workspaceMemberRole as dbWorkspaceMemberRole,
} from "./db/schema";
import logger from "./logger";
import { WorkspaceMember } from "./types";

export async function onboardUser({
  email,
  workspaceName,
}: {
  email: string;
  workspaceName: string;
}): Promise<Result<null, Error>> {
  const workspaces = await db().query.workspace.findMany({
    where: eq(dbWorkspace.name, workspaceName),
  });

  const workspace = workspaces[0];
  if (!workspace) {
    return err(new Error("Workspace not found"));
  }

  const maybeWorkspaceMember = await db().query.workspaceMember.findFirst({
    where: and(
      eq(dbWorkspaceMember.email, email),
      eq(dbWorkspaceMember.workspaceId, workspace.id)
    ),
  });

  let workspaceMember: WorkspaceMember;
  if (maybeWorkspaceMember) {
    workspaceMember = maybeWorkspaceMember;
  } else {
    workspaceMember = unwrap(
      await insert({
        table: dbWorkspaceMember,
        doNothingOnConflict: true,
        lookupExisting: and(
          eq(dbWorkspaceMember.email, email),
          eq(dbWorkspaceMember.workspaceId, workspace.id)
        ),
        values: {
          email,
          workspaceId: workspace.id,
        },
      }),
    );
  }

  if (workspaces.length > 1) {
    return err(new Error("workspaceName is not unique"));
  }

  logger().info(
    {
      workspaceMember,
      workspace,
    },
    "assigning role to workspace member",
  );

  await db()
    .insert(dbWorkspaceMemberRole)
    .values({
      workspaceId: workspace.id,
      workspaceMemberId: workspaceMember.id,
      role: "Admin",
    })
    .onConflictDoUpdate({
      target: [
        dbWorkspaceMemberRole.workspaceId,
        dbWorkspaceMemberRole.workspaceMemberId,
      ],
      set: { role: "Admin" },
    });

  return ok(null);
}
