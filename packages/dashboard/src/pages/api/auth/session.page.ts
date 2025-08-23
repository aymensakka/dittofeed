import { NextApiRequest, NextApiResponse } from "next";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // Proxy the session check to the API
  try {
    const response = await fetch("http://localhost:3001/api/public/auth/session", {
      headers: {
        // Forward all cookies from the request
        cookie: req.headers.cookie || "",
      },
    });
    
    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ authenticated: false, error: "Failed to check session" });
  }
}