import { NextApiRequest, NextApiResponse } from "next";
import { serialize } from "cookie";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Set test cookies
  const cookies = [
    serialize("df-workspace", "test-workspace-id", {
      httpOnly: false,
      secure: false,
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 14, // 14 days
      path: "/",
    }),
    serialize("df-email", "test@example.com", {
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
  ];
  
  res.setHeader("Set-Cookie", cookies);
  res.status(200).json({ message: "Test cookies set successfully" });
}