import { DittofeedSdk } from "@dittofeed/sdk-node";
import backendConfigFromLib from "backend-lib/src/config";
import { getFeatures } from "backend-lib/src/features";
import backendLogger from "backend-lib/src/logger";
import { getRequestContext as getRequestContextFromLib } from "backend-lib/src/requestContext";
import {
  DFRequestContext,
  OpenIdProfile,
  RequestContextErrorType as BackendRequestContextErrorType,
} from "backend-lib/src/types";
import {
  SINGLE_TENANT_LOGIN_PAGE,
  UNAUTHORIZED_PAGE,
} from "isomorphic-lib/src/constants";
import { assertUnreachable } from "isomorphic-lib/src/typeAssertions";
import { err, ok, Result } from "neverthrow";
import { GetServerSideProps, NextApiRequest } from "next";

import { apiBase } from "./apiBase";
import { GetDFServerSideProps, PropsWithInitialState } from "./types";
import { checkMultiTenantSession } from "./multiTenantAuth";

const backendConfig = backendConfigFromLib;
const logger = backendLogger;
const getRequestContext = getRequestContextFromLib;

export const requestContext: <T>(
  gssp: GetDFServerSideProps<PropsWithInitialState<T>>,
) => GetServerSideProps<PropsWithInitialState<T>> =
  (gssp) => async (context) => {
    const { profile } = context.req as { profile?: OpenIdProfile };
    
    // For multi-tenant mode, check session via API
    if (backendConfig().authMode === "multi-tenant") {
      const session = await checkMultiTenantSession(context.req as any, context.res as any);
      if (session) {
        console.log("Multi-tenant session found:", session);
        console.log("JWT token available:", !!session.jwt);
        
        // Add JWT to authorization header if available
        const headers: any = {
          ...context.req.headers,
          "x-workspace-id": session.workspaceId,
        };
        
        if (session.jwt) {
          headers.authorization = `Bearer ${session.jwt}`;
        }
        
        console.log("Calling getRequestContext with workspace:", session.workspaceId, "JWT:", !!session.jwt);
        const rc = await getRequestContext(headers, undefined);
        console.log("Request context result:", rc.isOk() ? "OK" : rc.error);
        if (rc.isOk()) {
          const features = await getFeatures({
            workspaceId: rc.value.workspace.id,
          });
          return gssp(context, { ...rc.value, features });
        } else {
          console.error("Request context failed:", rc.error);
        }
      }
    }
    
    const rc = await getRequestContext(context.req.headers, profile);
    const { onboardingUrl } = backendConfig();
    if (rc.isErr()) {
      const { error } = rc;
      switch (error.type) {
        case BackendRequestContextErrorType.EmailNotVerified:
          logger().info(
            {
              onboardingUrl,
              email: error.email,
            },
            "email not verified",
          );
          return {
            redirect: {
              destination: onboardingUrl,
              basePath: false,
              permanent: false,
            },
          };
        case BackendRequestContextErrorType.NotOnboarded:
          logger().info(
            {
              contextErrorMsg: error.message,
            },
            "user not onboarded",
          );
          return {
            redirect: {
              destination: onboardingUrl,
              permanent: false,
              basePath: false,
            },
          };
        case BackendRequestContextErrorType.Unauthorized: {
          logger().info(
            {
              contextErrorMsg: error.message,
            },
            "user unauthorized",
          );

          return {
            redirect: {
              destination: error.action.url,
              permanent: false,
              basePath: false,
            },
          };
        }
        case BackendRequestContextErrorType.ApplicationError:
          throw new Error(error.message);
        case BackendRequestContextErrorType.NotAuthenticated:
          if (backendConfig().authMode === "single-tenant") {
            return {
              redirect: {
                destination: SINGLE_TENANT_LOGIN_PAGE,
                permanent: false,
              },
            };
          }
          // For multi-tenant, redirect to OAuth login
          if (backendConfig().authMode === "multi-tenant") {
            const authProvider = backendConfig().authProvider || "google";
            // Include the basePath in the returnUrl
            const returnUrl = `/dashboard${context.resolvedUrl}`;
            return {
              redirect: {
                destination: `http://localhost:3001/api/public/auth/oauth2/initiate/${authProvider}?returnUrl=${encodeURIComponent(returnUrl)}`,
                permanent: false,
                basePath: false,
              },
            };
          }
          return {
            redirect: {
              destination: UNAUTHORIZED_PAGE,
              permanent: false,
            },
          };
        case BackendRequestContextErrorType.WorkspaceInactive:
          logger().info(
            {
              contextErrorMsg: error.message,
              workspace: error.workspace,
            },
            "workspace inactive",
          );
          return {
            redirect: { destination: UNAUTHORIZED_PAGE, permanent: false },
          };
        default:
          assertUnreachable(error);
      }
    }

    const { dashboardWriteKey, trackDashboard } = backendConfig();

    if (dashboardWriteKey && trackDashboard) {
      await DittofeedSdk.init({
        writeKey: dashboardWriteKey,
        host: apiBase(),
      });
    }

    const dfContext = rc.value;
    const features = await getFeatures({
      workspaceId: dfContext.workspace.id,
    });

    DittofeedSdk.identify({
      userId: dfContext.member.id,
      traits: {
        workspaceId: dfContext.workspace.id,
        email: dfContext.member.email,
        firstName: dfContext.member.name,
        nickname: dfContext.member.nickname,
        createdAt: dfContext.member.createdAt,
        emailVerified: dfContext.member.emailVerified,
      },
    });

    return gssp(context, { ...dfContext, features });
  };

export interface ApiRequestContextError {
  message: string;
  status: number;
}

export async function apiAuth(
  req: NextApiRequest,
): Promise<Result<DFRequestContext, ApiRequestContextError>> {
  const rc = await getRequestContext(req.headers, undefined);

  if (rc.isOk()) {
    return ok(rc.value);
  }

  const { error } = rc;
  logger().info({ backendError: error }, "API Auth Error from backend-lib");

  switch (error.type) {
    case BackendRequestContextErrorType.NotAuthenticated:
      return err({
        message: "Authentication required.",
        status: 401,
      });
    case BackendRequestContextErrorType.Unauthorized:
      return err({
        message: error.message || "Unauthorized",
        status: 401,
      });
    case BackendRequestContextErrorType.EmailNotVerified:
      return err({
        message: `Email not verified: ${error.email}`,
        status: 403,
      });
    case BackendRequestContextErrorType.NotOnboarded:
      return err({
        message: error.message || "User not onboarded.",
        status: 403,
      });
    case BackendRequestContextErrorType.WorkspaceInactive:
      return err({
        message: error.message || "Workspace is inactive.",
        status: 403,
      });
    case BackendRequestContextErrorType.ApplicationError:
      return err({
        message: error.message || "Internal Server Error.",
        status: 500,
      });
    default:
      assertUnreachable(error);
      return err({
        message: "An unexpected authentication error occurred.",
        status: 500,
      });
  }
}
