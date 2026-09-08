import type {
  FastifyReply,
  FastifyRequest,
} from 'fastify'

import { registerBodySchema } from './auth.schema.js'
import {
  EmailAlreadyInUseError,
  registerUser,
} from './auth.service.js'

export async function registerController(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const parsedBody = registerBodySchema.safeParse(
    request.body,
  )

  if (!parsedBody.success) {
    return reply.status(400).send({
      code: 'VALIDATION_ERROR',
      fields: parsedBody.error.flatten().fieldErrors,
    })
  }

  try {
    const user = await registerUser(parsedBody.data)

    return reply.status(201).send({
      user: {
        id: user.id,
        name: user.account_display_name,
        email: user.email,
      },
    })
  } catch (error) {
    if (error instanceof EmailAlreadyInUseError) {
      return reply.status(409).send({
        code: 'EMAIL_ALREADY_IN_USE',
      })
    }

    throw error
  }
}