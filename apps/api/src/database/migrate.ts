import { createHash } from 'node:crypto'
import { readdir, readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

import pg from 'pg'

import { env } from '../config/env.js'

const { Client } = pg

const migrationsDirectory = fileURLToPath(
  new URL('../../../../database/migrations/', import.meta.url),
)

function createChecksum(content: string) {
  return createHash('sha256').update(content).digest('hex')
}

async function runMigrations() {
  if (!env.databaseDirectUrl) {
    throw new Error('DATABASE_DIRECT_URL is not configured')
  }

  const client = new Client({
    connectionString: env.databaseDirectUrl,
  })

  await client.connect()

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `)

    const files = (await readdir(migrationsDirectory))
      .filter((file) => file.endsWith('.sql'))
      .sort()

    for (const filename of files) {
      const migrationPath = new URL(
        `../../../../database/migrations/${filename}`,
        import.meta.url,
      )

      const sql = await readFile(migrationPath, 'utf8')
      const checksum = createChecksum(sql)

      const migration = await client.query<{
        checksum: string
      }>(
        `
          SELECT checksum
          FROM schema_migrations
          WHERE filename = $1
        `,
        [filename],
      )

      if (migration.rowCount) {
        const previousChecksum = migration.rows[0].checksum

        if (previousChecksum !== checksum) {
          throw new Error(
            `Migration ${filename} was modified after being executed`,
          )
        }

        console.log(`Skipping ${filename}`)
        continue
      }

      console.log(`Running ${filename}`)

      try {
        await client.query('BEGIN')

        await client.query(sql)

        await client.query(
          `
            INSERT INTO schema_migrations (
              filename,
              checksum
            )
            VALUES ($1, $2)
          `,
          [filename, checksum],
        )

        await client.query('COMMIT')

        console.log(`Completed ${filename}`)
      } catch (error) {
        await client.query('ROLLBACK')
        throw error
      }
    }
  } finally {
    await client.end()
  }
}

runMigrations().catch((error) => {
  console.error(error)
  process.exit(1)
})