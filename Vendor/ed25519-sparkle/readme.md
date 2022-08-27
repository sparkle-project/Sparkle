Ed25519
=======

This is a portable implementation of [Ed25519](http://ed25519.cr.yp.to/) based
on the SUPERCOP "ref10" implementation. Additionally there is key exchanging
and scalar addition included to further aid building a PKI using Ed25519. All
code is licensed under the permissive zlib license.

All code is pure ANSI C without any dependencies, except for the random seed
generation which uses standard OS cryptography APIs (`CryptGenRandom` on
Windows, `/dev/urandom` on nix). If you wish to be entirely portable define
`ED25519_NO_SEED`. This disables the `ed25519_create_seed` function, so if your
application requires key generation you must supply your own seeding function
(which is simply a 256 bit (32 byte) cryptographic random number generator).


Performance
-----------

On a Windows machine with an Intel Pentium B970 @ 2.3GHz I got the following
speeds (running on only one a single core):

    Seed generation: 64us (15625 per second)
    Key generation: 88us (11364 per second)
    Message signing (short message): 87us (11494 per second)
    Message verifying (short message): 228us (4386 per second)
    Scalar addition: 100us (10000 per second)
    Key exchange: 220us (4545 per second)

The speeds on other machines may vary. Sign/verify times will be higher with
longer messages. The implementation significantly benefits from 64 bit
architectures, if possible compile as 64 bit.


Usage
-----

Simply add all .c and .h files in the `src/` folder to your project and include
`ed25519.h` in any file you want to use the API. If you prefer to use a shared
library, only copy `ed25519.h` and define `ED25519_DLL` before importing. A
windows DLL is pre-built.

There are no defined types for seeds, private keys, public keys, shared secrets
or signatures. Instead simple `unsigned char` buffers are used with the
following sizes:

```c
unsigned char seed[32];
unsigned char signature[64];
unsigned char public_key[32];
unsigned char private_key[64];
unsigned char scalar[32];
unsigned char shared_secret[32];
```

API
---

```c
int ed25519_create_seed(unsigned char *seed);
```

Creates a 32 byte random seed in `seed` for key generation. `seed` must be a
writable 32 byte buffer. Returns 0 on success, and nonzero on failure.

```c
void ed25519_create_keypair(unsigned char *public_key, unsigned char *private_key,
                            const unsigned char *seed);
```

Creates a new key pair from the given seed. `public_key` must be a writable 32
byte buffer, `private_key` must be a writable 64 byte buffer and `seed` must be
a 32 byte buffer.

```c
void ed25519_sign(unsigned char *signature,
                  const unsigned char *message, size_t message_len,
                  const unsigned char *public_key, const unsigned char *private_key);
```

Creates a signature of the given message with the given key pair. `signature`
must be a writable 64 byte buffer. `message` must have at least `message_len`
bytes to be read. 

```c
int ed25519_verify(const unsigned char *signature,
                   const unsigned char *message, size_t message_len,
                   const unsigned char *public_key);
```

Verifies the signature on the given message using `public_key`. `signature`
must be a readable 64 byte buffer. `message` must have at least `message_len`
bytes to be read. Returns 1 if the signature matches, 0 otherwise.

```c
void ed25519_add_scalar(unsigned char *public_key, unsigned char *private_key,
                        const unsigned char *scalar);
```

Adds `scalar` to the given key pair where scalar is a 32 byte buffer (possibly
generated with `ed25519_create_seed`), generating a new key pair. You can
calculate the public key sum without knowing the private key and vice versa by
passing in `NULL` for the key you don't know. This is useful for enforcing
randomness on a key pair by a third party while only knowing the public key,
among other things.  Warning: the last bit of the scalar is ignored - if
comparing scalars make sure to clear it with `scalar[31] &= 127`.


```c
void ed25519_key_exchange(unsigned char *shared_secret,
                          const unsigned char *public_key, const unsigned char *private_key);
```

Performs a key exchange on the given public key and private key, producing a
shared secret. It is recommended to hash the shared secret before using it.
`shared_secret` must be a 32 byte writable buffer where the shared secret will
be stored.

Example
-------

```c
unsigned char seed[32], public_key[32], private_key[64], signature[64];
unsigned char other_public_key[32], other_private_key[64], shared_secret[32];
const unsigned char message[] = "TEST MESSAGE";

/* create a random seed, and a key pair out of that seed */
if (ed25519_create_seed(seed)) {
    printf("error while generating seed\n");
    exit(1);
}

ed25519_create_keypair(public_key, private_key, seed);

/* create signature on the message with the key pair */
ed25519_sign(signature, message, strlen(message), public_key, private_key);

/* verify the signature */
if (ed25519_verify(signature, message, strlen(message), public_key)) {
    printf("valid signature\n");
} else {
    printf("invalid signature\n");
}

/* create a dummy keypair to use for a key exchange, normally you'd only have
the public key and receive it through some communication channel */
if (ed25519_create_seed(seed)) {
    printf("error while generating seed\n");
    exit(1);
}

ed25519_create_keypair(other_public_key, other_private_key, seed);

/* do a key exchange with other_public_key */
ed25519_key_exchange(shared_secret, other_public_key, private_key);

/* 
    the magic here is that ed25519_key_exchange(shared_secret, public_key,
    other_private_key); would result in the same shared_secret
*/

```

License
-------
All code is released under the zlib license. See license.txt for details.
