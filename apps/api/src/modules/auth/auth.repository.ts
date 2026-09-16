import type { PoolClient } from "pg";
import { pool } from "../../database/pool.js";

type CreateUserInput = {
  name: string;
  email: string;
};

type CreateSessionInput = {
  userId: string;
  sessionTokenHash: string;
  expiresAt: Date;
  userAgent?: string | null;
};

export async function createUser(client: PoolClient, input: CreateUserInput) {
  const result = await client.query<{
    id: string;
    account_display_name: string;
    email: string;
  }>(
    `
      INSERT INTO users (
        account_display_name,
        email,
        account_type
      )
      VALUES ($1, $2, 'FULL')
      RETURNING
        id,
        account_display_name,
        email
    `,
    [input.name, input.email],
  );

  return result.rows[0];
}

export async function createPasswordCredential(
  client: PoolClient,
  userId: string,
  passwordHash: string,
) {
  await client.query(
    `
      INSERT INTO auth_credentials (
        user_id,
        type,
        secret_hash
      )
      VALUES ($1, 'EMAIL_PASSWORD', $2)
    `,
    [userId, passwordHash],
  );
}

export async function findUserCredentialByEmail(email: string) {
  const result = await pool.query<{
    id: string;
    account_display_name: string;
    email: string;
    status: string;
    secret_hash: string;
  }>(
    `
      SELECT
        u.id,
        u.account_display_name,
        u.email,
        u.status,
        ac.secret_hash
      FROM users u
      INNER JOIN auth_credentials ac
        ON ac.user_id = u.id
        AND ac.type = 'EMAIL_PASSWORD'
      WHERE LOWER(u.email) = LOWER($1)
      LIMIT 1
    `,
    [email],
  );

  return result.rows[0] ?? null;
}

export async function createUserSession(input: CreateSessionInput) {
  await pool.query(
    `
      INSERT INTO user_sessions (
        user_id,
        session_token_hash,
        user_agent,
        expires_at
      )
      VALUES ($1, $2, $3, $4)
    `,
    [
      input.userId,
      input.sessionTokenHash,
      input.userAgent ?? null,
      input.expiresAt,
    ],
  );
}

export async function findUserBySessionTokenHash(
  sessionTokenHash: string,
) {
  const result = await pool.query<{
    id: string;
    account_display_name: string;
    email: string;
  }>(
    `
      SELECT
        u.id,
        u.account_display_name,
        u.email
      FROM user_sessions us
      INNER JOIN users u
        ON u.id = us.user_id
      WHERE us.session_token_hash = $1
        AND us.revoked_at IS NULL
        AND us.expires_at > NOW()
        AND u.status = 'ACTIVE'
      LIMIT 1
    `,
    [sessionTokenHash],
  );

  return result.rows[0] ?? null;
}

export async function revokeUserSession(
  sessionTokenHash: string,
) {
  await pool.query(
    `
      UPDATE user_sessions
      SET revoked_at = NOW()
      WHERE session_token_hash = $1
        AND revoked_at IS NULL
    `,
    [sessionTokenHash],
  );
}