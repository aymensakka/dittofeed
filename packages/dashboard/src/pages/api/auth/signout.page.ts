import { serialize } from "cookie";
import { NextApiRequest, NextApiResponse } from "next";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== "GET" && req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  // Clear all authentication cookies
  const cookies = [
    // Clear JWT cookie
    serialize("df-jwt", "", {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: -1, // Delete immediately
    }),
    // Clear transfer cookie if it exists
    serialize("df-jwt-transfer", "", {
      httpOnly: false,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: -1,
    }),
    // Clear any session cookies
    serialize("df-session", "", {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: -1,
    }),
  ];

  res.setHeader("Set-Cookie", cookies);

  // Redirect to login page
  const redirectUrl = process.env.NEXT_PUBLIC_AUTH_MODE === "multi-tenant" 
    ? "/dashboard/auth/login"
    : "/";

  if (req.method === "GET") {
    return res.redirect(redirectUrl);
  } else {
    return res.status(200).json({ success: true, redirectUrl });
  }
}