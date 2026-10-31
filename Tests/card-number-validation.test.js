"use strict";
function luhnIsValid(value) {
  const digits = String(value).replace(/\D/g, '');
  if (digits.length < 12 || digits.length > 19) return false;
  let sum = 0; let doubleDigit = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let n = Number(digits[i]);
    if (doubleDigit) { n *= 2; if (n > 9) n -= 9; }
    sum += n; doubleDigit = !doubleDigit;
  }
  return sum % 10 === 0;
}
const cases = [["4111111111111111", true], ["5555555555554444", true], ["4111111111111112", false], ["123", false]];
for (const [value, expected] of cases) if (luhnIsValid(value) !== expected) throw new Error(`Luhn case failed: ${value}`);
process.stdout.write(`Card-number validation passed (${cases.length} cases).\n`);
