import { act } from 'react'
import { render, screen } from '@testing-library/react'
import { expect, it } from 'vitest'

import { Calendar } from '../../../../packages/ui/src/Calendar/Calendar'

// Guards the react-day-picker 8 -> 10 migration: the custom MonthCaption reads
// navigation off useDayPicker() instead of the removed useNavigation(), so the
// caption and the day grid must still advance together on next/previous.
it('advances caption and grid together', async () => {
  render(<Calendar mode='single' defaultMonth={new Date(2026, 0, 15)} />)

  expect(screen.getByText('January 2026')).toBeTruthy()

  await act(async () => screen.getByLabelText('Next month').click())

  expect(screen.getByText('February 2026')).toBeTruthy()
  expect(screen.queryByText('January 2026')).toBeNull()

  await act(async () => screen.getByLabelText('Previous month').click())

  expect(screen.getByText('January 2026')).toBeTruthy()
})
