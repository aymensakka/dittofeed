import { Workspace } from "@prisma/client";
import { randomUUID } from "crypto";

import { segmentIdentifyEvent } from "../test/factories/segment";
import config from "./config";
import prisma from "./prisma";
import writeAssignments from "./segments/computePropertiesWorkflow/activities/computeProperties/writeAssignments";
import { SegmentNodeType, SegmentOperatorType } from "./types";
import {
  findAllUserTraits,
  findManyEvents,
  submitBroadcast,
} from "./userEvents";
import { insertUserEvents } from "./userEvents/clickhouse";

describe("userEvents", () => {
  let workspace: Workspace;
  beforeEach(async () => {
    workspace = await prisma().workspace.create({
      data: { name: `workspace-${randomUUID()}` },
    });
  });

  describe("findAllUserTraits", () => {
    beforeEach(async () => {
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

  describe("findManyEvents", () => {
    let messageId1: string;
    let messageId2: string;
    beforeEach(async () => {
      messageId1 = randomUUID();
      messageId2 = randomUUID();

      await insertUserEvents({
        tableVersion: config().defaultUserEventsTableVersion,
        workspaceId: workspace.id,
        events: [
          {
            messageId: messageId1,
            messageRaw: segmentIdentifyEvent({
              messageId1,
              timestamp: "2015-02-23T22:28:55.111Z",
              traits: {
                status: "onboarding",
                name: "max",
              },
            }),
          },
          {
            messageId: messageId2,
            messageRaw: segmentIdentifyEvent({
              timestamp: "2015-01-23T22:28:55.111Z",
              messageId: messageId2,
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
      const events = await findManyEvents({
        workspaceId: workspace.id,
        tableVersion: config().defaultUserEventsTableVersion,
      });
      if (!events[0] || !events[1]) {
        throw new Error("Too few events found.");
      }
      expect(new Date(events[0].event_time).getTime()).toBeGreaterThan(
        new Date(events[1].event_time).getTime()
      );
    });
  });

  describe("submitBroadcast", () => {
    beforeEach(async () => {
      // insert events, compute assignments
    });

    it("broadcasts to all users in in the workspace", async () => {
      // await writeAssignments({
      //   workspaceId: workspace.id,
      //   currentTime: Date.now(),
      //   userProperties: [],
      //   tableVersion: config().defaultUserEventsTableVersion,
      //   segments: [
      //     {
      //       id: randomUUID(),
      //       workspaceId: workspace.id,
      //       name: "broadcast segment",
      //       definition: {
      //         entryNode: {
      //           id: "1",
      //           type: SegmentNodeType.Broadcast,
      //         },
      //         nodes: [],
      //       },
      //       createdAt: new Date(),
      //       updatedAt: new Date(),
      //     },
      //     {
      //       id: randomUUID(),
      //       workspaceId: workspace.id,
      //       name: "unrelated segment",
      //       definition: {
      //         entryNode: {
      //           id: "1",
      //           type: SegmentNodeType.Trait,
      //           path: "foo",
      //           operator: {
      //             type: SegmentOperatorType.Equals,
      //             value: "bar",
      //           },
      //         },
      //         nodes: [],
      //       },
      //       createdAt: new Date(),
      //       updatedAt: new Date(),
      //     },
      //   ],
      // });
    });
  });
});
