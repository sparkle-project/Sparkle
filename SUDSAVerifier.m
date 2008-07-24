//
//  SUDSAVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

// DSA stuff adapted from code provided by Allan Odgaard. Thanks, Allan!

#import "SUDSAVerifier.h"

#import <stdio.h>
#import <openssl/evp.h>
#import <openssl/bio.h>
#import <openssl/pem.h>
#import <openssl/rsa.h>
#import <openssl/sha.h>

long b64decode(unsigned char* str)
{
    unsigned char *cur, *start;
    int d, dlast, phase;
    unsigned char c;
    static int table[256] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 00-0F */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 10-1F */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,  /* 20-2F */
        52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,  /* 30-3F */
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,  /* 40-4F */
        15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,  /* 50-5F */
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,  /* 60-6F */
        41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,  /* 70-7F */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 80-8F */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 90-9F */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* A0-AF */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* B0-BF */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* C0-CF */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* D0-DF */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* E0-EF */
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1   /* F0-FF */
    };
	
    d = dlast = phase = 0;
    start = str;
    for (cur = str; *cur != '\0'; ++cur )
    {
		if(*cur == '\n' || *cur == '\r'){phase = dlast = 0; continue;}
        d = table[(int)*cur];
        if(d != -1)
        {
            switch(phase)
            {
				case 0:
					++phase;
					break;
				case 1:
					c = ((dlast << 2) | ((d & 0x30) >> 4));
					*str++ = c;
					++phase;
					break;
				case 2:
					c = (((dlast & 0xf) << 4) | ((d & 0x3c) >> 2));
					*str++ = c;
					++phase;
					break;
				case 3:
					c = (((dlast & 0x03 ) << 6) | d);
					*str++ = c;
					phase = 0;
					break;
            }
            dlast = d;
        }
    }
    *str = '\0';
    return str - start;
}

EVP_PKEY* load_dsa_key(char *key)
{
	EVP_PKEY* pkey = NULL;
	BIO *bio;
	if((bio = BIO_new_mem_buf(key, (int)strlen(key))))
	{
		DSA* dsa_key = 0;
		if(PEM_read_bio_DSA_PUBKEY(bio, &dsa_key, NULL, NULL))
		{
			if((pkey = EVP_PKEY_new()))
			{
				if(EVP_PKEY_assign_DSA(pkey, dsa_key) != 1)
				{
					DSA_free(dsa_key);
					EVP_PKEY_free(pkey);
					pkey = NULL;
				}
			}
		}
		BIO_free(bio);
	}
	return pkey;
}

@implementation SUDSAVerifier

+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString
{
	BOOL result = NO;
	if (!encodedSignature) { return NO; }
	if (!pkeyString) { return NO; }
	
	// Remove whitespace around each line of the key.
	NSMutableArray *pkeyTrimmedLines = [NSMutableArray array];
	NSEnumerator *pkeyLinesEnumerator = [[pkeyString componentsSeparatedByString:@"\n"] objectEnumerator];
	NSString *pkeyLine;
	while ((pkeyLine = [pkeyLinesEnumerator nextObject]) != nil)
	{
		[pkeyTrimmedLines addObject:[pkeyLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	}
	pkeyString = [pkeyTrimmedLines componentsJoinedByString:@"\n"]; // Put them back together.

	EVP_PKEY* pkey = NULL;
	pkey = load_dsa_key((char *)[pkeyString UTF8String]);
	if (!pkey) { return NO; }

	// Now, the signature is in base64; we have to decode it into a binary stream.
	unsigned char *signature = (unsigned char *)[encodedSignature UTF8String];
	long length = b64decode(signature); // Decode the signature in-place and get the new length of the signature string.
	
	// We've got the signature, now get the file data.
	NSData *pathData = [NSData dataWithContentsOfFile:path];
	if (!pathData) { return NO; }
	
	// Hash the file with SHA-1.
	unsigned char md[SHA_DIGEST_LENGTH];
	SHA1([pathData bytes], [pathData length], md);
	
	// Actually verify the signature on the file.
	EVP_MD_CTX ctx;
	if(EVP_VerifyInit(&ctx, EVP_dss1()) == 1) // We're using DSA keys.
	{
		EVP_VerifyUpdate(&ctx, md, SHA_DIGEST_LENGTH);
		result = (EVP_VerifyFinal(&ctx, signature, (unsigned int)length, pkey) == 1);
	}
	
	EVP_PKEY_free(pkey);
	return result;
}

@end
