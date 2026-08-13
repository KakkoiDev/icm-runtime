import { createParamDecorator } from '@nestjs/common'

/**
 * @deprecated Use `@Context()` from `src/prisma/context.decorator` instead.
 */
export const LegacyUser = createParamDecorator(() => {
  return null
})
