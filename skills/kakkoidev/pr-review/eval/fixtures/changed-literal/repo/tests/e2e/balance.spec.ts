import { Label } from './constants'

test('balance summary shows cost row', async () => {
  await assertAmount(Label.COST_PRICE, '¥251')
})
