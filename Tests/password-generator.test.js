'use strict';
const assert = require('assert');
if (!globalThis.crypto || typeof globalThis.crypto.getRandomValues !== 'function') {
  globalThis.crypto = require('node:crypto').webcrypto;
}
const generator = require('../Extension/password-generator.js');

for (const length of [12, 16, 24, 32, 48, 64]) {
  const value = generator.generatePassword({ length });
  assert.strictEqual(value.length, length, 'expected a ' + length + '-character password');
  assert(/[A-Z]/.test(value), 'uppercase class should be represented');
  assert(/[a-z]/.test(value), 'lowercase class should be represented');
  assert(/[2-9]/.test(value), 'number class should be represented');
  assert(/[!@#$%^&*()\-_=+\[\]{}:,.?]/.test(value), 'symbol class should be represented');
  assert(!/[Il1O0]/.test(value), 'ambiguous characters should be excluded by default');
}

const lowerOnly = generator.generatePassword({
  length: 20, uppercase: false, lowercase: true, numbers: false, symbols: false
});
assert.strictEqual(lowerOnly.length, 20);
assert(/^[a-z]+$/.test(lowerOnly), 'single selected class should be respected');

const allClasses = generator.generatePassword({
  length: 24, uppercase: true, lowercase: true, numbers: true, symbols: true,
  excludeAmbiguous: false
});
assert(/[A-Z]/.test(allClasses) && /[a-z]/.test(allClasses) && /[0-9]/.test(allClasses));

assert.throws(() => generator.generatePassword({ length: 8 }), /12 and 64/);
assert.throws(() => generator.generatePassword({
  length: 16, uppercase: false, lowercase: false, numbers: false, symbols: false
}), /at least one/);

for (const count of [4, 6, 8, 10]) {
  const phrase = generator.generatePassphrase(count, '-');
  assert.strictEqual(phrase.split('-').length, count, 'expected ' + count + ' words');
}
assert.strictEqual(generator.generatePassphrase(5, ' ').split(' ').length, 5);
assert.throws(() => generator.generatePassphrase(3), /4 and 10/);
assert(generator.estimatePasswordBits(24) > 100, 'default password search-space estimate should be substantial');
assert(generator.estimatePassphraseBits(6) > 30, 'six-word passphrase estimate should be positive');
assert(generator.wordListSize >= 100, 'passphrase word list should contain at least 100 entries');

process.stdout.write('Password generator tests passed (password options, ambiguity, passphrases, and estimates).\n');
