import fastifyCors from "@fastify/cors";
import { FastifyInstance } from "fastify";
import fp from "fastify-plugin";
import config from "backend-lib/src/config";

// eslint-disable-next-line @typescript-eslint/require-await
// Using fastify-plugin to ensure it is installed globally
const cors = fp(async (fastify: FastifyInstance) => {
  const { authMode } = config();
  
  // For multi-tenant mode with credentials, we need to specify exact origins
  const corsOptions = authMode === "multi-tenant" ? {
    origin: (origin: string | undefined, callback: any) => {
      // Allow requests from the dashboard origin
      const allowedOrigins = [
        "http://localhost:3000",
        "http://localhost:3001",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:3001",
      ];
      
      // Allow requests with no origin (same-origin requests)
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error("Not allowed by CORS"));
      }
    },
    credentials: true,
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allowedHeaders: ["Content-Type", "Authorization", "x-workspace-id", "x-api-key", "x-write-key"],
    exposedHeaders: ["Content-Disposition"],
  } : {
    // For other auth modes, use the original configuration
    origin: "*",
    methods: "*",
    allowedHeaders: "*",
    exposedHeaders: ["Content-Disposition"],
  };
  
  await fastify.register(fastifyCors, corsOptions);
});
export default cors;
