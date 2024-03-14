import { Cl } from '@stacks/transactions';
import { describe, expect, it } from 'vitest';

const accounts = simnet.getAccounts();
const address1 = accounts.get('wallet_1')!;

describe('test `increment` public function', () => {
  it('increments the count by the given value', () => {
    const incrementResponse = simnet.callPublicFn('counter', 'increment', [Cl.uint(1)], address1);
    console.log(Cl.prettyPrint(incrementResponse.result)); // (ok u2)
    expect(incrementResponse.result).toBeOk(Cl.uint(2));

    const count1 = simnet.getDataVar('counter', 'count');
    expect(count1).toBeUint(2);

    simnet.callPublicFn('counter', 'increment', [Cl.uint(40)], address1);
    const count2 = simnet.getDataVar('counter', 'count');
    expect(count2).toBeUint(42);
  });

  it('sends a print event', () => {
    const incrementResponse = simnet.callPublicFn('counter', 'increment', [Cl.uint(1)], address1);

    expect(incrementResponse.events).toHaveLength(1);
    const printEvent = incrementResponse.events[0];
    expect(printEvent.event).toBe('print_event');
    expect(printEvent.data.value).toBeTuple({
      object: Cl.stringAscii('count'),
      action: Cl.stringAscii('incremented'),
      value: Cl.uint(2),
    });
  });
});