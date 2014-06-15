//
//  SUDSAVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright (c) 2014 Big Nerd Ranch. All rights reserved.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright (c) 2011 Mark Hamlin. All rights reserved.
//

#import "SUDSAVerifier.h"
#include <CommonCrypto/CommonDigest.h>

#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_7

#pragma mark - CSSM implementation helpers

SU_ALWAYS_INLINE CSSM_DATA su_createData(NSData * bytes)
{
	return (CSSM_DATA){
		.Data = (UInt8 *)bytes.bytes,
		.Length = bytes.length
	};
}

static NSData *su_cssm_getKeyData(NSString *key)
{
	if ( (key == nil) || ([key length] == 0) ) return nil;
	NSMutableString *t = [key mutableCopy];

	// Remove the PEM guards (if present)
	[t replaceOccurrencesOfString:@"-" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [t length])];
	[t replaceOccurrencesOfString:@"BEGIN PUBLIC KEY" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [t length])];
	[t replaceOccurrencesOfString:@"END PUBLIC KEY" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [t length])];

	// Remove any line feeds from the beginning of the key
	while ( [t characterAtIndex:0] == '\n' ) {
		[t deleteCharactersInRange:NSMakeRange(0, 1)];
	}

	// Remove any line feeds at the end of the key
	while ( [t characterAtIndex:[t length] - 1] == '\n' ) {
		[t deleteCharactersInRange:NSMakeRange([t length] - 1, 1)];
	}

	// Remove whitespace around each line of the key.
	NSMutableArray *pkeyTrimmedLines = [NSMutableArray array];
	NSCharacterSet *whiteSet = [NSCharacterSet whitespaceCharacterSet];
	for (NSString *pkeyLine in [t componentsSeparatedByString:@"\n"])
	{
		[pkeyTrimmedLines addObject:[pkeyLine stringByTrimmingCharactersInSet:whiteSet]];
	}
	key = [pkeyTrimmedLines componentsJoinedByString:@"\n"]; // Put them back together.

	// Base64 decode to return the raw key bits (DER format rather than PEM)
	return [[NSData alloc] initWithBase64Encoding:key];
}

#pragma mark - CSSM implemention

static CSSM_VERSION vers = { 2, 0 };
static const CSSM_GUID su_guid = { 'S', 'p', 'a', { 'r', 'k', 'l', 'e', 0, 0, 0, 0 } };
static CSSM_BOOL cssmInited = CSSM_FALSE;

static void *su_cssm_malloc( CSSM_SIZE size, void *__unused ref ) { return malloc( size ); }
static void su_cssm_free( void *ptr, void *__unused ref ) { free( ptr ); }
static void *su_cssm_realloc( void *ptr, CSSM_SIZE size, void *__unused ref ) { return realloc( ptr, size ); }
static void *su_cssm_calloc( uint32 num, CSSM_SIZE size, void *__unused ref ) { return calloc( num, size ); }

static CSSM_API_MEMORY_FUNCS su_cssm_memFuncs = {
	su_cssm_malloc,
	su_cssm_free,
	su_cssm_realloc,
	su_cssm_calloc,
	NULL
};

static CSSM_CSP_HANDLE su_cdsa_init( void )
{
	CSSM_CSP_HANDLE cspHandle = CSSM_INVALID_HANDLE;
	CSSM_RETURN crtn;

	if ( !cssmInited ) {
		CSSM_PVC_MODE pvcPolicy = CSSM_PVC_NONE;
		crtn = CSSM_Init( &vers, CSSM_PRIVILEGE_SCOPE_NONE, &su_guid, CSSM_KEY_HIERARCHY_NONE, &pvcPolicy, NULL );
		if ( crtn ) return CSSM_INVALID_HANDLE;
		cssmInited = CSSM_TRUE;
	}

	crtn = CSSM_ModuleLoad( &gGuidAppleCSP, CSSM_KEY_HIERARCHY_NONE, NULL, NULL );
	if ( crtn ) return CSSM_INVALID_HANDLE;

	crtn = CSSM_ModuleAttach( &gGuidAppleCSP, &vers, &su_cssm_memFuncs, 0, CSSM_SERVICE_CSP, 0, CSSM_KEY_HIERARCHY_NONE, NULL, 0, NULL, &cspHandle );
	if ( crtn ) return CSSM_INVALID_HANDLE;

	return cspHandle;
}

static void su_cssm_release( CSSM_CSP_HANDLE cspHandle )
{
	if ( CSSM_ModuleDetach(cspHandle) != CSSM_OK ) return;
	CSSM_ModuleUnload( &gGuidAppleCSP, NULL, NULL );
}

static CSSM_KEY_PTR su_cdsa_createKey(NSData *rawKey)
{
	if (!rawKey.length) return NULL;

	CSSM_KEY_PTR retval = su_cssm_calloc(sizeof(CSSM_KEY), 1, NULL);
	if (!retval) return NULL;

	CSSM_KEYHEADER_PTR hdr = &(retval->KeyHeader);
	hdr->HeaderVersion = CSSM_KEYHEADER_VERSION;
	hdr->CspId = su_guid;
	hdr->BlobType = CSSM_KEYBLOB_RAW;
	hdr->Format = CSSM_KEYBLOB_RAW_FORMAT_X509;
	hdr->AlgorithmId = CSSM_ALGID_DSA;
	hdr->KeyClass = CSSM_KEYCLASS_PUBLIC_KEY;
	hdr->KeyAttr = CSSM_KEYATTR_EXTRACTABLE;
	hdr->KeyUsage = CSSM_KEYUSE_ANY;

	retval->KeyData = su_createData(rawKey);

	return retval;
}

static BOOL su_cdsa_verifyKey(CSSM_CSP_HANDLE cspHandle, CSSM_KEY_PTR key)
{
	if (cspHandle == CSSM_INVALID_HANDLE || !key) return NO;
	if (key->KeyHeader.LogicalKeySizeInBits == 0 ) {
		CSSM_RETURN crtn;
		CSSM_KEY_SIZE keySize;

		/* This will fail if the key isn't valid */
		crtn = CSSM_QueryKeySizeInBits( cspHandle, CSSM_INVALID_HANDLE, key, &keySize );
		if ( crtn ) return NO;
		key->KeyHeader.LogicalKeySizeInBits = keySize.LogicalKeySizeInBits;
	}
	return YES;
}

static BOOL su_cdsa_verifySignature( CSSM_CSP_HANDLE cspHandle, const CSSM_KEY_PTR key, NSData *msg, NSData *signature )
{
	if (!msg || !signature) return NO;

	CSSM_CC_HANDLE ccHandle = CSSM_INVALID_HANDLE;
	CSSM_DATA plain = su_createData(msg), cipher = su_createData(signature);

	if (CSSM_CSP_CreateSignatureContext(cspHandle, CSSM_ALGID_SHA1WithDSA, NULL, key, &ccHandle) != CSSM_OK) {
		return NO;
	}

	BOOL ret = (CSSM_VerifyData(ccHandle, &plain, 1, CSSM_ALGID_NONE, &cipher) == CSSM_OK);
	CSSM_DeleteContext(ccHandle);
	return ret;
}

static NSData *su_ccsm_SHA1DigestWithStream(NSInputStream *inputStream) {
	if (!inputStream) return nil;

	static const size_t chunkSize = PAGE_MAX_SIZE;

	[inputStream open];

	// Initialize the hash object
	CC_SHA1_CTX context;
	CC_SHA1_Init(&context);

	// Feed the data to the hash object
	while (inputStream.hasBytesAvailable) {
		uint8_t buffer[chunkSize];
		NSInteger readCount = [inputStream read:buffer maxLength:chunkSize];

		if (readCount < 0) {
			[inputStream close];
			return nil;
		}

		CC_SHA1_Update(&context, (const void *)buffer, (CC_LONG)readCount);

		if (readCount == 0) { break; }
	}

	[inputStream close];

	NSMutableData *result = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(result.mutableBytes, &context);
	return [result copy];
}

#pragma mark - Security weak imports

extern OSStatus SecItemImport(CFDataRef importedData, CFStringRef fileNameOrExtension, SecExternalFormat *inputFormat, SecExternalItemType *itemType, SecItemImportExportFlags			flags, const SecItemImportExportKeyParameters *keyParams, SecKeychainRef importKeychain, CFArrayRef *outItems) WEAK_IMPORT_ATTRIBUTE;
extern SecGroupTransformRef SecTransformCreateGroupTransform(void) WEAK_IMPORT_ATTRIBUTE;
extern SecTransformRef SecTransformCreateReadTransformWithReadStream(CFReadStreamRef inputStream) WEAK_IMPORT_ATTRIBUTE;
extern SecTransformRef SecDigestTransformCreate(CFTypeRef digestType, CFIndex digestLength, CFErrorRef* error) WEAK_IMPORT_ATTRIBUTE;
extern SecTransformRef SecVerifyTransformCreate(SecKeyRef key, CFDataRef signature, CFErrorRef* error) WEAK_IMPORT_ATTRIBUTE;
extern SecGroupTransformRef SecTransformConnectTransforms(SecTransformRef sourceTransformRef, CFStringRef sourceAttributeName, SecTransformRef destinationTransformRef, CFStringRef destinationAttributeName, SecGroupTransformRef group, CFErrorRef *error) WEAK_IMPORT_ATTRIBUTE;
extern CFTypeRef SecTransformExecute(SecTransformRef transformRef, CFErrorRef* errorRef)  WEAK_IMPORT_ATTRIBUTE CF_RETURNS_RETAINED;

#endif

@implementation SUDSAVerifier {
	SecKeyRef _secKey;
#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_7
	NSData *_cssmKeyData;
	CSSM_KEY_PTR _cssmKey;
	CSSM_CSP_HANDLE _cspHandle;
#endif
}

+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString
{
	if (!encodedSignature || !path) return NO;

	SUDSAVerifier *verifier = [[self alloc] initWithPublicKeyString:pkeyString];

	if (!verifier) return NO;

	NSString *strippedSignature = [encodedSignature stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSData *signature = [[NSData alloc] initWithBase64Encoding:strippedSignature];
	return [verifier verifyFileAtPath:path signature:signature];
}

- (instancetype)initWithPublicKeyString:(NSString *)string
{
#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_7
	if (SecItemImport == NULL) {
		if (!string.length) return (self = nil);
		self = [super init];
		if (!self) return nil;

		_cssmKeyData = su_cssm_getKeyData(string);
		_cssmKey = su_cdsa_createKey(_cssmKeyData); // Create the DSA key
		_cspHandle = su_cdsa_init();

		if (!su_cdsa_verifyKey(_cspHandle, _cssmKey)) { return (self = nil); };
		return self;
	}
#endif

	NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
	return (self = [self initWithPublicKeyData:data]);
}

- (instancetype)initWithPublicKeyData:(NSData *)data
{
#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_7
	if (SecItemImport == NULL) {
		NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		return (self = [self initWithPublicKeyString:string]);
	}
#endif

	if (!data.length) return (self = nil);

	self = [super init];
	if (!self) return nil;

	SecExternalFormat format = kSecFormatOpenSSL;
	SecExternalItemType itemType = kSecItemTypePublicKey;
	SecItemImportExportKeyParameters params = {};
	CFArrayRef items = NULL;

	OSStatus status = SecItemImport((__bridge CFDataRef)data, NULL, &format, &itemType, 0, &params, NULL, &items);
	if (status || !items) { return (self = nil); }

	if (format == kSecFormatOpenSSL && itemType == kSecItemTypePublicKey && CFArrayGetCount(items) == 1) {
		_secKey = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
	}

	CFRelease(items);

	return self;
}

- (void)dealloc
{
	if (_secKey) { CFRelease(_secKey); }
#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_7
	if (_cspHandle) { su_cssm_release(_cspHandle); }
	if (_cssmKey) { su_cssm_free(_cssmKey, NULL); }
#endif
}

- (BOOL)verifyURL:(NSURL *)URL signature:(NSData *)signature
{
	NSInputStream *dataInputStream = [NSInputStream inputStreamWithURL:URL];
	return [self verifyStream:dataInputStream signature:signature];
}

- (BOOL)verifyFileAtPath:(NSString *)path signature:(NSData *)signature
{
	if (!path.length) return NO;
	NSInputStream *dataInputStream = [NSInputStream inputStreamWithFileAtPath:path];
	return [self verifyStream:dataInputStream signature:signature];
}

- (BOOL)verifyStream:(NSInputStream *)stream signature:(NSData *)signature
{
#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_7
	if (SecItemImport == NULL) {
		NSData *hashData = su_ccsm_SHA1DigestWithStream(stream);
		return su_cdsa_verifySignature(_cspHandle, _cssmKey, hashData, signature);
	}
#endif

	if (!stream || !signature) { return NO; }

	__block SecGroupTransformRef group = SecTransformCreateGroupTransform();
	__block SecTransformRef dataReadTransform = NULL;
	__block SecTransformRef dataDigestTransform = NULL;
	__block SecTransformRef dataVerifyTransform = NULL;
	__block CFErrorRef error = NULL;

	BOOL(^cleanup)(void) = ^{
		if (group) CFRelease(group);
		if (dataReadTransform) CFRelease(dataReadTransform);
		if (dataDigestTransform) CFRelease(dataDigestTransform);
		if (dataVerifyTransform) CFRelease(dataVerifyTransform);
		if (error) CFRelease(error);
		return NO;
	};

	dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)stream);
	if (!dataReadTransform) { return cleanup(); }

	dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, CC_SHA1_DIGEST_LENGTH, NULL);
	if (!dataDigestTransform) { return cleanup(); }

	dataVerifyTransform = SecVerifyTransformCreate(_secKey, (__bridge CFDataRef)signature, NULL);
	if (!dataVerifyTransform) { return cleanup(); }

	SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error);
	if (error) { return cleanup(); }
	SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataVerifyTransform, kSecTransformInputAttributeName, group, &error);
	if (error) { return cleanup(); }

	NSNumber *result = CFBridgingRelease(SecTransformExecute(group, NULL));
	cleanup();
	return result.boolValue;
}

@end
