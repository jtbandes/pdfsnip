//
//  main.m
//  pdfsnip
//
//  Created by Jacob Bandes-Storch on 2/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

void readXObject(const char *key, CGPDFObjectRef value, void (^callback)(CGImageRef image, const char *key));
void printme(const char *key, CGPDFObjectRef value, void *info);
CGColorRenderingIntent getRenderingIntentFromDictionary(CGPDFDictionaryRef dict);
CGColorSpaceRef copyColorSpaceFromObject(CGPDFObjectRef object, CGPDFInteger bitsPerComponent, CGFloat **defaultDecode);
bool getNumbersFromArray(CGPDFArrayRef array, size_t n, CGPDFReal *values);

int main(int argc, const char * argv[])
{

	@autoreleasepool {
		
		NSURL *file = [NSURL fileURLWithPath:[[[NSProcessInfo processInfo] arguments] objectAtIndex:1]];
		NSURL *baseURL = [NSURL fileURLWithPath:[[[NSProcessInfo processInfo] arguments] objectAtIndex:2]];
		
		CGPDFDocumentRef doc = CGPDFDocumentCreateWithURL((__bridge CFURLRef)file);
		if (!doc) {
			printf("Error opening PDF file %s.\n", [[file absoluteString] UTF8String]);
			exit(1);
		}
		
		printf("%zu pages\n", CGPDFDocumentGetNumberOfPages(doc));
		
		// Scan every page
		size_t pages = CGPDFDocumentGetNumberOfPages(doc);
		for (int i = 1; i <= pages; i++) {
			CGPDFDictionaryRef dict = CGPDFPageGetDictionary(CGPDFDocumentGetPage(doc, i));
			printf("%zu items in page %d:", CGPDFDictionaryGetCount(dict), i);
			CGPDFDictionaryApplyFunction(dict, &printme, NULL);
			printf("\n");
			
			if (!CGPDFDictionaryGetDictionary(dict, "Resources", &dict)) {
				printf("No Resources for page %d, skipping\n", i);
				continue;
			}
			
			if (!CGPDFDictionaryGetDictionary(dict, "XObject", &dict)) {
				printf("No XObject for page %d, skipping\n", i);
				continue;
			}
			
			// Read the XObjects
			printf("=== Page %d\n", i);
			CGPDFDictionaryApplyFunction(dict, (CGPDFDictionaryApplierFunction)&readXObject, (__bridge void *)^(CGImageRef image, const char *key) {
				
				CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[baseURL URLByAppendingPathComponent:
																								 [NSString stringWithFormat:@"p%d-%s.jpg", i, key]],
																			 kUTTypeJPEG, 1, NULL);
				CGImageDestinationAddImage(dest, image, NULL);
				if (!CGImageDestinationFinalize(dest)) {
					printf("Error writing image %s\n", key);
				}
				CFRelease(dest);
			});
			
		}
		
		CGPDFDocumentRelease(doc);
		
	}
    return 0;
}

void printme(const char *key, CGPDFObjectRef value, void *info)
{
	printf(" %s/%d", key, CGPDFObjectGetType(value));
}

void readXObject(const char *key, CGPDFObjectRef value, void (^callback)(CGImageRef image, const char *key))
{
	if (CGPDFObjectGetType(value) != kCGPDFObjectTypeStream) {
		printf("Unknown object type %d for XObject %s\n", CGPDFObjectGetType(value), key);
		return;
	}
	
	CGPDFStreamRef stream;
	if (!CGPDFObjectGetValue(value, kCGPDFObjectTypeStream, &stream)) {
		printf("Error reading stream for XObject %s\n", key);
		return;
	}
	CGPDFDictionaryRef dict = CGPDFStreamGetDictionary(stream);
	
	const char *name;
	if (!CGPDFDictionaryGetName(dict, "Subtype", &name)) {
		printf("Error reading name for XObject %s\n", key);
		return;
	}
	else if (strcmp(name, "Image") != 0) {
		printf("Unknown subtype %s for XObject %s\n", name, key);
		return;
	}
	
	// Read the image
	CGPDFInteger width, height, bitsPerComponent;
	CGPDFBoolean interpolate = false;
	CGColorSpaceRef csp;
	CGPDFArrayRef decodeArray;
	size_t numComponents;
	CGColorRenderingIntent intent = kCGRenderingIntentDefault;
	CGFloat *decode = NULL;
	
	if (!CGPDFDictionaryGetInteger(dict, "Width", &width)) {
		printf("Error reading Width\n");
		return;
	}
	if (!CGPDFDictionaryGetInteger(dict, "Height", &height)) {
		printf("Error reading Height\n");
		return;
	}
	if (!CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bitsPerComponent)) {
		printf("Error reading BitsPerComponent\n");
	}
	CGPDFDictionaryGetBoolean(dict, "Interpolate", &interpolate);
	
	CGPDFObjectRef cspObject;
	if (!CGPDFDictionaryGetObject(dict, "ColorSpace", &cspObject)) {
		printf("Error reading ColorSpace\n");
	}
	printf("Image %s: ", key);
	csp = copyColorSpaceFromObject(cspObject, bitsPerComponent, &decode);
	if (!csp) {
		printf("Error reading color space object\n");
		return;
	}
	intent = getRenderingIntentFromDictionary(dict);
	numComponents = CGColorSpaceGetNumberOfComponents(csp);
	
	CGFloat *defaultDecode = decode;
	if (CGPDFDictionaryGetArray(dict, "Decode", &decodeArray)) {
		decode = malloc(2 * numComponents * sizeof(CGFloat));
		if (getNumbersFromArray(decodeArray, 2 * numComponents, decode)) {
			printf("Decode:");
			for (int i = 0; i < 2*numComponents; i++) {
				printf(" %.2f", decode[i]);
			}
			printf("\n");
			free(defaultDecode);
		}
		else {
			printf("Error reading Decode values\n");
			free(decode);
			decode = defaultDecode;
		}
	}
	else {
//		printf("Error reading Decode\n");
	}
	
	
	CGPDFDataFormat fmt;
	CFDataRef data = CGPDFStreamCopyData(stream, &fmt);
	CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
	CFRelease(data);
	
	CGImageRef image;
	
	switch (fmt) {
		case CGPDFDataFormatRaw:
			image = CGImageCreate(width,
								  height,
								  bitsPerComponent,
								  bitsPerComponent * numComponents,
								  ceil(bitsPerComponent * numComponents * width / 8.0),
								  csp,
								  0,
								  provider,
								  decode,
								  interpolate,
								  intent);
			break;
			
		case CGPDFDataFormatJPEGEncoded:
		case CGPDFDataFormatJPEG2000:
			image = CGImageCreateWithJPEGDataProvider(provider,
													  decode,
													  interpolate,
													  intent);
			break;
			
		default:
			printf("Unknown data format %d\n", fmt);
			break;
	}
	if (!image) {
		printf("bad image\n");
	}
	
	free(decode);
	
	callback(image, key);
	
	CGImageRelease(image);
}

CGColorRenderingIntent getRenderingIntentFromDictionary(CGPDFDictionaryRef dict)
{
	const char *name;
	if (!CGPDFDictionaryGetName(dict, "Intent", &name)) {
		return kCGRenderingIntentDefault;
	}
	
	if (strcmp(name, "AbsoluteColorimetric") == 0) {
		return kCGRenderingIntentAbsoluteColorimetric;
	}
	else if (strcmp(name, "RelativeColorimetric") == 0) {
		return kCGRenderingIntentRelativeColorimetric;
	}
	else if (strcmp(name, "Saturation") == 0) {
		return kCGRenderingIntentSaturation;
	}
	else if (strcmp(name, "Perceptual") == 0) {
		return kCGRenderingIntentPerceptual;
	}
	else {
		printf("Unknown rendering intent %s\n", name);
		return kCGRenderingIntentDefault;
	}
}
			
CGColorSpaceRef copyColorSpaceFromObject(CGPDFObjectRef object, CGPDFInteger bitsPerComponent, CGFloat **defaultDecode)
{
	// Unsupported: default color space from the resource dictionary,
	// Pattern, Indexed, Separation, DeviceN
	
	CGFloat *dummy = NULL;
	if (!defaultDecode) defaultDecode = &dummy;
	
	CGColorSpaceRef csp = NULL;
	
	if (CGPDFObjectGetType(object) == kCGPDFObjectTypeName) {
		const char *name;
		if (CGPDFObjectGetValue(object, kCGPDFObjectTypeName, &name)) {
			printf("Reading %s color space\n", name);
			if (strcmp(name, "DeviceGray") == 0) {
				*defaultDecode = malloc(2 * sizeof(CGFloat));
				memcpy(*defaultDecode, ((const CGFloat[2]){0, 1}), 2 * sizeof(CGFloat));
				csp = CGColorSpaceCreateDeviceGray();
			}
			else if (strcmp(name, "DeviceRGB") == 0) {
				*defaultDecode = malloc(6 * sizeof(CGFloat));
				memcpy(*defaultDecode, ((const CGFloat[6]){0, 1, 0, 1, 0, 1}), 6 * sizeof(CGFloat));
				csp = CGColorSpaceCreateDeviceRGB();
			}
			else if (strcmp(name, "DeviceCMYK") == 0) {
				*defaultDecode = malloc(8 * sizeof(CGFloat));
				memcpy(*defaultDecode, ((const CGFloat[8]){0, 1, 0, 1, 0, 1, 0, 1}), 8 * sizeof(CGFloat));
				csp = CGColorSpaceCreateDeviceCMYK();
			}
			else {
				printf("Unknown color space name %s\n", name);
			}
		}
		else {
			printf("Error reading color space name\n");
		}
	}
	
	else if (CGPDFObjectGetType(object) == kCGPDFObjectTypeArray) {
		
		CGPDFArrayRef array;
		CGPDFObjectGetValue(object, kCGPDFObjectTypeArray, &array);
		
		CGPDFDictionaryRef cspDict;
		CGPDFArrayRef cspArray;
		CGPDFObjectRef cspObject;
		CGPDFStringRef cspString;
		CGPDFStreamRef cspStream;
		
		const char *name;
		if (CGPDFArrayGetName(array, 0, &name)) {
			printf("Reading %s color space\n", name);
			
			if (strcmp(name, "CalGray") == 0) {
				CGPDFReal whitePoint[3];
				CGPDFReal blackPoint[3] = {0, 0, 0};
				CGPDFReal gamma = 1;
				
				if (CGPDFArrayGetDictionary(array, 1, &cspDict)) {
					// Optional
					if (!(CGPDFDictionaryGetArray(cspDict, "BlackPoint", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(blackPoint), blackPoint))) {
//						printf("Error reading (optional) CalGray BlackPoint\n");
					}
					if (!CGPDFDictionaryGetNumber(cspDict, "Gamma", &gamma)) {
//						printf("Error reading (optional) CalGray Gamma\n");
					}
					// Required
					if (!(CGPDFDictionaryGetArray(cspDict, "WhitePoint", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(whitePoint), whitePoint))) {
						printf("Error reading CalGray WhitePoint\n");
					}
					else {
						*defaultDecode = malloc(2 * sizeof(CGFloat));
						memcpy(*defaultDecode, ((const CGFloat[2]){0, 1}), 2 * sizeof(CGFloat));
						csp = CGColorSpaceCreateCalibratedGray(whitePoint, blackPoint, gamma);
					}
				}
				else {
					printf("Error reading CalGray color space\n");
				}
			}
			
			else if (strcmp(name, "CalRGB") == 0) {
				CGPDFReal whitePoint[3];
				CGPDFReal blackPoint[3] = {0, 0, 0};
				CGPDFReal gamma[3] = {1, 1, 1};
				CGPDFReal matrix[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
				
				if (CGPDFArrayGetDictionary(array, 1, &cspDict)) {
					// Optional
					if (!(CGPDFDictionaryGetArray(cspDict, "BlackPoint", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(blackPoint), blackPoint))) {
//						printf("Error reading (optional) CalRGB BlackPoint\n");
					}
					if (!(CGPDFDictionaryGetArray(cspDict, "Matrix", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(matrix), matrix))) {
//						printf("Error reading (optional) CalRGB Matrix\n");
					}
					if (!(CGPDFDictionaryGetArray(cspDict, "Gamma", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(gamma), gamma))) {
//						printf("Error reading (optional) CalRGB Gamma\n");
					}
					// Required
					if (!(CGPDFDictionaryGetArray(cspDict, "WhitePoint", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(whitePoint), whitePoint))) {
						printf("Error reading CalRGB WhitePoint\n");
					}
					else {
						*defaultDecode = malloc(6 * sizeof(CGFloat));
						memcpy(*defaultDecode, ((const CGFloat[6]){0, 1, 0, 1, 0, 1}), 6 * sizeof(CGFloat));
						csp = CGColorSpaceCreateCalibratedRGB(whitePoint, blackPoint, gamma, matrix);
					}
				}
				else {
					printf("Error reading CalGray color space\n");
				}
			}
			
			else if (strcmp(name, "Lab") == 0) {
				CGPDFReal whitePoint[3];
				CGPDFReal blackPoint[3] = {0, 0, 0};
				CGPDFReal range[4] = {-100, 100, -100, 100};
				
				if (CGPDFArrayGetDictionary(array, 1, &cspDict)) {
					// Optional
					if (!(CGPDFDictionaryGetArray(cspDict, "BlackPoint", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(blackPoint), blackPoint))) {
//						printf("Error reading (optional) Lab BlackPoint\n");
					}
					if (!(CGPDFDictionaryGetArray(cspDict, "Range", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(range), range))) {
//						printf("Error reading (optional) Lab Range\n");
					}
					// Required
					if (!(CGPDFDictionaryGetArray(cspDict, "WhitePoint", &cspArray) &&
						  getNumbersFromArray(cspArray, sizeof(whitePoint), whitePoint))) {
						printf("Error reading Lab WhitePoint\n");
					}
					else {
						*defaultDecode = malloc(6 * sizeof(CGFloat));
						memcpy(*defaultDecode, ((const CGFloat[6]){0, 100, range[0], range[1], range[2], range[3]}), 6 * sizeof(CGFloat));
						csp = CGColorSpaceCreateLab(whitePoint, blackPoint, range);
					}
				}
				else {
					printf("Error reading Lab color space\n");
				}
			}
			
			else if (strcmp(name, "ICCBased") == 0) {
				CGColorSpaceRef alternate = NULL;
				CGPDFInteger numComponents;
				CGDataProviderRef profile;
				CGPDFReal *range = (CGPDFReal[8]){0, 1, 0, 1, 0, 1, 0, 1};
				
				if (CGPDFArrayGetStream(array, 1, &cspStream)) {
					cspDict = CGPDFStreamGetDictionary(cspStream);
					
					// Required
					if (!CGPDFDictionaryGetInteger(cspDict, "N", &numComponents)) {
						printf("Error reading ICCBased N\n");
					}
					else if (!(numComponents == 1 || numComponents == 3 || numComponents == 4)) {
						printf("Bad value for ICCBased N: %ld\n", numComponents);
					}
					else {
						// Optional
						if (!(CGPDFDictionaryGetObject(cspDict, "Alternate", &cspObject) &&
							  (alternate = copyColorSpaceFromObject(cspObject, bitsPerComponent, NULL)))) {
//							printf("Error reading (optional) ICCBased Alternate\n");
						}
						if (!(CGPDFDictionaryGetArray(cspDict, "Range", &cspArray) &&
							  getNumbersFromArray(cspArray, 2 * numComponents, range))) {
//							printf("Error reading (optional) ICCBased Range\n");
						}
						
						CFDataRef data = CGPDFStreamCopyData(cspStream, NULL);
						profile = CGDataProviderCreateWithCFData(data);
//						CFRelease(data);
						
//						if (CGPDFDictionaryGetStream(cspDict, "Metadata", &cspStream)) {
//							
//						} else {
//							printf("Error reading ICCBased Metadata\n");
//						}
						
						csp = CGColorSpaceCreateICCBased(numComponents, range, profile, alternate);
//						CGDataProviderRelease(profile);
						if (alternate) CGColorSpaceRelease(alternate);
						
						*defaultDecode = malloc(2 * numComponents * sizeof(CGFloat));
						memcpy(*defaultDecode, range, 2 * numComponents * sizeof(CGFloat));
					}
				}
				else {
					printf("Error reading ICCBased color space\n");
				}
			}
			
			else if (strcmp(name, "Indexed") == 0) {
				CGPDFObjectRef baseObject;
				CGColorSpaceRef base;
				CGPDFInteger highVal;
				CGPDFObjectRef lookup;
				
				// Required
				if (!(CGPDFArrayGetObject(array, 1, &baseObject) &&
					  (base = copyColorSpaceFromObject(baseObject, bitsPerComponent, NULL)))) {
					printf("Error reading Indexed base\n");
				}
				else if (!CGPDFArrayGetInteger(array, 2, &highVal)) {
					printf("Error reading Indexed highval\n");
				}
				else if (!CGPDFArrayGetObject(array, 3, &lookup)) {
					printf("Error reading Indexed lookup\n");
				}
				else {
					CFDataRef colorData = NULL;
					const unsigned char *colorTable = NULL;
					if (CGPDFObjectGetType(lookup) == kCGPDFObjectTypeStream &&
						CGPDFObjectGetValue(lookup, kCGPDFObjectTypeStream, &cspStream)) {
						colorData = CGPDFStreamCopyData(cspStream, NULL);
						colorTable = CFDataGetBytePtr(colorData);
					}
					else if (CGPDFObjectGetType(lookup) == kCGPDFObjectTypeString &&
							 CGPDFObjectGetValue(lookup, kCGPDFObjectTypeString, &cspString)) {
						colorTable = CGPDFStringGetBytePtr(cspString);
					}
					else {
						printf("Unknown Indexed lookup type %d\n", CGPDFObjectGetType(lookup));
					}
					
//					if (colorData) CFRelease(colorData);
					if (colorTable) {
						csp = CGColorSpaceCreateIndexed(base, highVal, colorTable);
//						size_t numComponents = CGColorSpaceGetNumberOfComponents(csp);
						
						*defaultDecode = malloc(2 * sizeof(CGFloat));
						memcpy(*defaultDecode, ((const CGFloat[2]){0, pow(2, bitsPerComponent)-1}), 2 * sizeof(CGFloat));
						
						return csp;
					}
				}
			}
			
			else {
				printf("Unknown color space name %s\n", name);
			}
		}
		else {
			printf("Error reading color space name from array\n");
		}
	}
	
	if (defaultDecode == &dummy && dummy) free(dummy);
	
	return csp;
}
			
bool getNumbersFromArray(CGPDFArrayRef array, size_t n, CGPDFReal *values)
{
	bool success = true;
	size_t count = CGPDFArrayGetCount(array);
	for (int i = 0; success && i < count && i < n; i++) {
		success = success && CGPDFArrayGetNumber(array, i, &values[i]);
		if (!success) {
			printf("Error getting number at index %d from array\n", i);
		}
	}
	return success;
}
