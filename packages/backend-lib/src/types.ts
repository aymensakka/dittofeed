import { Journey, Segment, UserProperty } from "@prisma/client";
import { Static, Type } from "@sinclair/typebox";
import {
  EventType,
  JourneyDefinition,
  Nullable,
  SegmentDefinition,
  UserPropertyDefinition,
} from "isomorphic-lib/src/types";

export * from "isomorphic-lib/src/types";

export enum KafkaMessageTypes {
  JSON = "0",
}

export interface EnrichedSegment extends Omit<Segment, "definition"> {
  definition: SegmentDefinition;
}

export interface EnrichedJourney extends Omit<Journey, "definition"> {
  definition: JourneyDefinition;
}

export interface EnrichedUserProperty extends Omit<UserProperty, "definition"> {
  definition: UserPropertyDefinition;
}

export const ComputedAssignment = Type.Object({
  user_id: Type.String(),
  in_segment: Nullable(Type.Number()),
  user_property: Nullable(Type.String()),
  model_index: Type.Number(),
  history_length: Type.String(),
  latest_processing_time: Type.String(),
});

export type ComputedAssignment = Static<typeof ComputedAssignment>;

export const UserEvent = Type.Object({
  event_type: Type.Enum(EventType),
  user_id: Nullable(Type.String()),
  anonymous_id: Nullable(Type.String()),
  user_or_anonymous_id: Type.String(),
  event_time: Type.String(),
  processing_time: Type.String(),
  message_raw: Type.String(),
  event: Type.String(),
  workspace_id: Type.String(),
});

export type UserEvent = Static<typeof UserEvent>;

export * from "@prisma/client";

export enum InternalEventType {
  MessageSent = "DittoFeedInternalMessageSent",
}
