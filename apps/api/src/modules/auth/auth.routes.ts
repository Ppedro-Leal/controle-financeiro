import type { FastifyInstance } from 'fastify'

import { registerController } from './auth.controller.js'

export async function authRoutes(
  app: FastifyInstance,
) {
  app.post('/register', registerController)
}