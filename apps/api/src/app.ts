import Fastify from 'fastify'

import { pool } from './database/pool.js'

export function buildApp() {
  const app = Fastify({
    logger: true,
  })

  app.get('/health', async () => {
    return {
      status: 'ok',
    }
  })

  app.get('/health/database', async () => {
    const result = await pool.query<{
      current_time: Date
      database_name: string
    }>(`
      SELECT
        NOW() AS current_time,
        current_database() AS database_name
    `)

    return {
      status: 'ok',
      database: result.rows[0].database_name,
      time: result.rows[0].current_time,
    }
  })

  return app
}