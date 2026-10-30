import { Label } from './constants'

test('profile summary shows display name row', async () => {
  await assertField(Label.DISPLAY_NAME, 'user-1')
})
