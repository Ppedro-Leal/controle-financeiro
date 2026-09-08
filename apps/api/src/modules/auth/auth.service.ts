import { randomBytes, scrypt } from 'node:crypto'

import { pool } from '../../database/pool.js'
import {
  createPasswordCredential,
  createUser,
} from './auth.repository.js'

import type { RegisterBody } from './auth.schema.js'

const SCRYPT_KEY_LENGTH = 64
const SCRYPT_COST = 32768
const SCRYPT_BLOCK_SIZE = 8
const SCRYPT_PARALLELIZATION = 3
const SCRYPT_MAX_MEMORY = 64 * 1024 * 1024

export class EmailAlreadyInUseError extends Error {}

function deriveKey(
  password: string,
  salt: Buffer,
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(
      password,
      salt,
      SCRYPT_KEY_LENGTH,
      {
        cost: SCRYPT_COST,
        blockSize: SCRYPT_BLOCK_SIZE,
        parallelization: SCRYPT_PARALLELIZATION,
        maxmem: SCRYPT_MAX_MEMORY,
      },
      (error, derivedKey) => {
        if (error) {
          reject(error)
          return
        }

        resolve(derivedKey)
      },
    )
  })
}

async function hashPassword(password: string) {
  const salt = randomBytes(16)

  const derivedKey = await deriveKey(
    password,
    salt,
  )

  return [
    'scrypt',
    SCRYPT_COST,
    SCRYPT_BLOCK_SIZE,
    SCRYPT_PARALLELIZATION,
    salt.toString('base64'),
    derivedKey.toString('base64'),
  ].join('$')
}

function isUniqueViolation(error: unknown) {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === '23505'
  )
}

export async function registerUser(
  input: RegisterBody,
) {
  const passwordHash = await hashPassword(
    input.password,
  )

  const client = await pool.connect()

  try {
    await client.query('BEGIN')

    const user = await createUser(client, {
      name: input.name,
      email: input.email,
    })

    await createPasswordCredential(
      client,
      user.id,
      passwordHash,
    )

    await client.query('COMMIT')

    return user
  } catch (error) {
    await client.query('ROLLBACK')

    if (isUniqueViolation(error)) {
      throw new EmailAlreadyInUseError()
    }

    throw error
  } finally {
    client.release()
  }
}