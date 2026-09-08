import 'dotenv/config'

const databaseUrl = process.env.DATABASE_URL

if (!databaseUrl) {
  throw new Error('DATABASE_URL is not configured')
}

const port = Number(process.env.PORT ?? 3333)

export const env = {
  databaseUrl,
  port,
}