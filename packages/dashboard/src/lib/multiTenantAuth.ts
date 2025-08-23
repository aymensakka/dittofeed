import { IncomingMessage, ServerResponse } from "http";
import { parse } from "cookie";

export interface MultiTenantSession {
  email: string;
  name?: string;
  picture?: string;
  workspaceId: string;
  jwt?: string;
}

export async function checkMultiTenantSession(
  req: IncomingMessage & { cookies?: any },
  res?: ServerResponse
): Promise<MultiTenantSession | null> {
  try {
    // Parse cookies from the request
    let cookies = req.cookies;
    if (!cookies && req.headers.cookie) {
      cookies = parse(req.headers.cookie);
    }
    
    // Check for authentication cookies
    const isAuthenticated = cookies?.["df-authenticated"] === "true";
    const workspaceId = cookies?.["df-workspace"];
    const email = cookies?.["df-email"];
    const name = cookies?.["df-name"];
    const picture = cookies?.["df-picture"];
    const jwt = cookies?.["df-jwt"] || cookies?.["df-jwt-transfer"];
    
    // Debug: Check what cookies we have
    console.log("Checking multi-tenant session:");
    console.log("  - cookies:", Object.keys(cookies || {}));
    console.log("  - authenticated:", isAuthenticated);
    console.log("  - workspace:", workspaceId);
    console.log("  - email:", email);
    console.log("  - jwt:", !!jwt);
    
    if (!isAuthenticated || !workspaceId || !email) {
      console.log("Missing required auth data, returning null");
      return null;
    }
    
    // Return session from cookies
    return {
      email,
      workspaceId,
      name: name || email.split('@')[0],
      picture: picture || undefined,
      jwt,
    };
  } catch (error) {
    console.error("Error checking multi-tenant session:", error);
    return null;
  }
}
