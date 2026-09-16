import type { FastifyInstance } from "fastify";

import {
  loginController,
  logoutController,
  meController,
  registerController,
} from "./auth.controller.js";

export async function authRoutes(
  app: FastifyInstance,
) {
  app.post(
    "/register",
    registerController,
  );

  app.post(
    "/login",
    loginController,
  );

  app.get(
    "/me",
    meController,
  );

  app.post(
    "/logout",
    logoutController,
  );
}