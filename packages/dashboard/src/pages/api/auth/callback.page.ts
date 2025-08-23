import { NextApiRequest, NextApiResponse } from "next";
import { serialize } from "cookie";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const { token, returnUrl } = req.query;
  
  console.log("Auth callback received - token:", token, "returnUrl:", returnUrl);
  
  if (!token || typeof token !== "string") {
    return res.status(400).json({ error: "Missing token" });
  }
  
  try {
    // Exchange the token for session data with the API
    const response = await fetch("http://localhost:3001/api/public/auth/auth/exchange", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ token }),
    });
    
    if (!response.ok) {
      console.error("Token exchange failed:", response.status);
      return res.status(400).json({ error: "Invalid token" });
    }
    
    const { session, jwt } = await response.json();
    console.log("Session data received:", session, "JWT received:", !!jwt);
    
    // Set cookies that the dashboard can read
    const cookies = [
      serialize("df-workspace", session.workspaceId, {
        httpOnly: false,
        secure: false, // Explicitly set to false for local development
        sameSite: "lax",
        maxAge: 60 * 60 * 24 * 14, // 14 days
        path: "/",
      }),
      serialize("df-email", session.email, {
        httpOnly: false,
        secure: false,
        sameSite: "lax",
        maxAge: 60 * 60 * 24 * 14, // 14 days
        path: "/",
      }),
      serialize("df-authenticated", "true", {
        httpOnly: false,
        secure: false,
        sameSite: "lax",
        maxAge: 60 * 60 * 24 * 14, // 14 days
        path: "/",
      }),
      serialize("df-name", session.name || "", {
        httpOnly: false,
        secure: false,
        sameSite: "lax",
        maxAge: 60 * 60 * 24 * 14, // 14 days
        path: "/",
      }),
    ];
    
    // Add JWT token as httpOnly cookie for security
    if (jwt) {
      cookies.push(
        serialize("df-jwt", jwt, {
          httpOnly: true, // Security: prevent JS access
          secure: false, // For local development
          sameSite: "lax",
          maxAge: 60 * 60 * 24 * 7, // 7 days
          path: "/",
        })
      );
      // Also store in localStorage for client-side API calls
      // We'll do this on the client side after redirect
      cookies.push(
        serialize("df-jwt-transfer", jwt, {
          httpOnly: false, // Allow JS access temporarily
          secure: false,
          sameSite: "lax",
          maxAge: 60, // 1 minute - just for transfer
          path: "/",
        })
      );
    }
    
    console.log("Setting cookies and redirecting to:", returnUrl);
    res.setHeader("Set-Cookie", cookies);
    
    // Redirect to the intended page
    const destination = typeof returnUrl === "string" ? returnUrl : "/dashboard/journeys";
    res.redirect(302, destination);
  } catch (error) {
    console.error("Error exchanging token:", error);
    res.status(500).json({ error: "Failed to authenticate" });
  }
}