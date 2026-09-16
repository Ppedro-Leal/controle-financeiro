import type {
  FastifyReply,
  FastifyRequest,
} from "fastify";

import {
  loginBodySchema,
  registerBodySchema,
} from "./auth.schema.js";

import {
  EmailAlreadyInUseError,
  getUserFromSessionToken,
  InvalidCredentialsError,
  loginUser,
  logoutUser,
  registerUser,
} from "./auth.service.js";

const SESSION_COOKIE_NAME = "session_token";

function getSessionCookieOptions() {
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: process.env.NODE_ENV === "production",
    path: "/",
  };
}

export async function registerController(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const parsedBody =
    registerBodySchema.safeParse(request.body);

  if (!parsedBody.success) {
    return reply.status(400).send({
      code: "VALIDATION_ERROR",
      fields:
        parsedBody.error.flatten().fieldErrors,
    });
  }

  try {
    const user = await registerUser(
      parsedBody.data,
    );

    return reply.status(201).send({
      user: {
        id: user.id,
        name: user.account_display_name,
        email: user.email,
      },
    });
  } catch (error) {
    if (
      error instanceof EmailAlreadyInUseError
    ) {
      return reply.status(409).send({
        code: "EMAIL_ALREADY_IN_USE",
      });
    }

    throw error;
  }
}

export async function loginController(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const parsedBody =
    loginBodySchema.safeParse(request.body);

  if (!parsedBody.success) {
    return reply.status(400).send({
      code: "VALIDATION_ERROR",
      fields:
        parsedBody.error.flatten().fieldErrors,
    });
  }

  try {
    const { user, session } =
      await loginUser(
        parsedBody.data,
        request.headers["user-agent"] ?? null,
      );

    reply.setCookie(
      SESSION_COOKIE_NAME,
      session.token,
      {
        ...getSessionCookieOptions(),
        expires: session.expiresAt,
      },
    );

    return reply.status(200).send({
      user: {
        id: user.id,
        name: user.account_display_name,
        email: user.email,
      },
    });
  } catch (error) {
    if (
      error instanceof InvalidCredentialsError
    ) {
      return reply.status(401).send({
        code: "INVALID_CREDENTIALS",
      });
    }

    throw error;
  }
}

export async function meController(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const sessionToken =
    request.cookies[SESSION_COOKIE_NAME];

  if (!sessionToken) {
    return reply.status(401).send({
      code: "UNAUTHENTICATED",
    });
  }

  const user =
    await getUserFromSessionToken(
      sessionToken,
    );

  if (!user) {
    reply.clearCookie(
      SESSION_COOKIE_NAME,
      getSessionCookieOptions(),
    );

    return reply.status(401).send({
      code: "UNAUTHENTICATED",
    });
  }

  return reply.status(200).send({
    user: {
      id: user.id,
      name: user.account_display_name,
      email: user.email,
    },
  });
}

export async function logoutController(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const sessionToken =
    request.cookies[SESSION_COOKIE_NAME];

  if (sessionToken) {
    await logoutUser(sessionToken);
  }

  reply.clearCookie(
    SESSION_COOKIE_NAME,
    getSessionCookieOptions(),
  );

  return reply.status(204).send();
}