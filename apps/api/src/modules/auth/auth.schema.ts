import { z } from 'zod'

export const registerBodySchema = z.object({
  name: z
    .string()
    .trim()
    .min(2)
    .max(120),

  email: z
    .string()
    .trim()
    .toLowerCase()
    .email()
    .max(255),

  password: z
    .string()
    .min(8)
    .max(128),
})

export type RegisterBody = z.infer<typeof registerBodySchema>