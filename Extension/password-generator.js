'use strict';

(function installVaultlinePasswordGenerator(root) {
  const WORDS = ["amber","anchor","apricot","arch","atlas","aurora","badger","bamboo","beacon","birch","bison","bluebird","boulder","breeze","brook","cactus","camera","canary","canyon","carbon","cedar","cello","cinder","citadel","clover","comet","copper","coral","cosmos","cricket","crystal","cypress","daisy","delta","denim","dolphin","dragon","drift","eagle","echo","ember","falcon","fern","fjord","flannel","flint","forest","fossil","galaxy","garden","ginger","glacier","goblin","golden","granite","harbor","hazel","helium","heron","honey","horizon","iceberg","indigo","island","ivory","jade","jasmine","jigsaw","juniper","kettle","kiwi","lantern","laurel","lemon","lilac","lizard","lotus","magnet","maple","marble","meadow","meteor","midnight","mint","mosaic","mountain","nebula","nectar","nickel","nightjar","north","oasis","ocean","olive","onyx","orchid","otter","panda","paper","pebble","pepper","phoenix","piano","picket","pine","planet","plum","pocket","polar","prism","quartz","rabbit","radar","rainbow","raven","ripple","river","robin","rocket","saffron","sailor","saturn","scarlet","shadow","silver","sketch","slate","solar","sparrow","spruce","squirrel","starling","storm","summit","sunrise","tangerine","thistle","thunder","timber","topaz","tractor","tulip","tundra","turtle","velvet","violet","volcano","walnut","willow","winter","wizard","wren","zephyr","zinc"];
  const UPPER = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const LOWER = 'abcdefghijklmnopqrstuvwxyz';
  const DIGITS = '0123456789';
  const SYMBOLS = '!@#$%^&*()-_=+[]{}:,.?';

  function secureIndex(max) {
    if (!Number.isInteger(max) || max < 1 || max > 256) {
      throw new Error('The random selection range is not supported.');
    }
    const provider = root.crypto;
    if (!provider || typeof provider.getRandomValues !== 'function') {
      throw new Error('A cryptographically secure random-number provider is unavailable.');
    }
    const bytes = new Uint8Array(1);
    const limit = Math.floor(256 / max) * max;
    do {
      provider.getRandomValues(bytes);
    } while (bytes[0] >= limit);
    return bytes[0] % max;
  }

  function poolsFor(options = {}) {
    const exclude = options.excludeAmbiguous !== false;
    const pools = [];
    if (options.uppercase !== false) pools.push(exclude ? 'ABCDEFGHJKLMNPQRSTUVWXYZ' : UPPER);
    if (options.lowercase !== false) pools.push(exclude ? 'abcdefghijkmnopqrstuvwxyz' : LOWER);
    if (options.numbers !== false) pools.push(exclude ? '23456789' : DIGITS);
    if (options.symbols !== false) pools.push(SYMBOLS);
    return pools.filter(pool => pool.length > 0);
  }

  function generatePassword(options = {}) {
    const length = Number(options.length ?? 24);
    if (!Number.isInteger(length) || length < 12 || length > 64) {
      throw new Error('Password length must be between 12 and 64 characters.');
    }
    const pools = poolsFor(options);
    if (!pools.length) throw new Error('Select at least one character type.');
    if (length < pools.length) throw new Error('The selected password length is too short for the required character types.');

    const alphabet = pools.join('');
    const result = pools.map(pool => pool[secureIndex(pool.length)]);
    while (result.length < length) result.push(alphabet[secureIndex(alphabet.length)]);

    // Fisher-Yates shuffle, using the same cryptographically secure sampler.
    for (let i = result.length - 1; i > 0; i -= 1) {
      const j = secureIndex(i + 1);
      [result[i], result[j]] = [result[j], result[i]];
    }
    return result.join('');
  }

  function estimatePasswordBits(length, options = {}) {
    const pools = poolsFor(options);
    if (!pools.length) throw new Error('Select at least one character type.');
    return Number(length) * Math.log2(pools.join('').length);
  }

  function generatePassphrase(wordCount = 6, separator = '-') {
    const count = Number(wordCount);
    if (!Number.isInteger(count) || count < 4 || count > 10) {
      throw new Error('Passphrase length must be between 4 and 10 words.');
    }
    const allowedSeparators = ['-', '.', '_', ' '];
    const joiner = allowedSeparators.includes(separator) ? separator : '-';
    return Array.from({ length: count }, () => WORDS[secureIndex(WORDS.length)]).join(joiner);
  }

  function estimatePassphraseBits(wordCount = 6) {
    const count = Number(wordCount);
    if (!Number.isInteger(count) || count < 4 || count > 10) {
      throw new Error('Passphrase length must be between 4 and 10 words.');
    }
    return count * Math.log2(WORDS.length);
  }

  const api = Object.freeze({
    generatePassword, estimatePasswordBits, generatePassphrase,
    estimatePassphraseBits, wordListSize: WORDS.length
  });
  root.VaultlinePasswordGenerator = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(globalThis);
