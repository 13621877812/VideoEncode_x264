//
//  X264Encoder.m
//  VideoEncode
//
//  Created by aipu on 2018/11/26.
//  Copyright © 2018 aipu. All rights reserved.
//

#import "X264Encoder.h"
#ifdef __cplusplus
extern "C" {
#endif
#include <libavutil/opt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#ifdef __cplusplus
};
#endif

@implementation X264Encoder
{
    AVCodecContext *pCodecCtx;
    AVCodec *pCodec;
    AVPacket packet;
    AVFrame *pFrame;
    int pictureSize;
    int frameCounter;
    int frameWidth;
    int frameHeight;
}
    
+ (instancetype)defaultX264Encoder
{
    X264Encoder *x264encoder = [[X264Encoder alloc] initX264Encoder:CGSizeMake(720, 1280) frameRate:30 maxKeyframeInterval:25 bitrate:1024*1000 profileLevel:@""];
    return x264encoder;
}

- (instancetype)initX264Encoder:(CGSize)videoSize
                      frameRate:(NSUInteger)frameRate
            maxKeyframeInterval:(CGFloat)maxKeyframeInterval
                        bitrate:(NSUInteger)bitrate
                   profileLevel:(NSString *)profileLevel
{
    self = [super init];
    if (self) {
        _videoSize = videoSize;
        _frameRate = frameRate;
        _maxKeyframeInterval = maxKeyframeInterval;
        _bitrate = bitrate;
        _profileLevel = profileLevel;
        [self setupEncoder];
    }
    return self;
}
    
- (void)setupEncoder
{
    avcodec_register_all();
    frameCounter = 0;
    frameWidth = self.videoSize.width;
    frameHeight = self.videoSize.height;
    // Param that must set
    pCodecCtx = avcodec_alloc_context3(pCodec);
    pCodecCtx->codec_id = AV_CODEC_ID_H264;
    pCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    pCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    pCodecCtx->width = frameWidth;
    pCodecCtx->height = frameHeight;
    pCodecCtx->time_base.num = 1;
    pCodecCtx->time_base.den = self.frameRate;
    pCodecCtx->bit_rate = self.bitrate;
    pCodecCtx->gop_size = self.maxKeyframeInterval;
    pCodecCtx->qmin = 10;
    pCodecCtx->qmax = 51;
    AVDictionary *param = NULL;
    if(pCodecCtx->codec_id == AV_CODEC_ID_H264) {
        av_dict_set(&param, "preset", "slow", 0);
        av_dict_set(&param, "tune", "zerolatency", 0);
    }
    pCodec = avcodec_find_encoder(pCodecCtx->codec_id);
    if (!pCodec) {
        NSLog(@"Can not find encoder!");
    }
    if (avcodec_open2(pCodecCtx, pCodec, &param) < 0) {
        NSLog(@"Failed to open encoder!");
    }
    pFrame = av_frame_alloc();
    pFrame->width = frameWidth;
    pFrame->height = frameHeight;
    pFrame->format = AV_PIX_FMT_YUV420P;
    avpicture_fill((AVPicture *)pFrame, NULL, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    pictureSize = avpicture_get_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    av_new_packet(&packet, pictureSize);
}

- (void)encoding:(CVPixelBufferRef)pixelBuffer timestamp:(CGFloat)timestamp
{
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    UInt8 *pY = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    UInt8 *pUV = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t pYBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    size_t pUVBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    UInt8 *pYUV420P = (UInt8 *)malloc(width * height * 3 / 2);
    UInt8 *pU = pYUV420P + (width * height);
    UInt8 *pV = pU + (width * height / 4);
    for(int i = 0; i < height; i++) {
        memcpy(pYUV420P + i * width, pY + i * pYBytes, width);
    }
    for(int j = 0; j < height / 2; j++) {
        for(int i = 0; i < width / 2; i++) {
            *(pU++) = pUV[i<<1];
            *(pV++) = pUV[(i<<1) + 1];
        }
        pUV += pUVBytes;
    }
    pFrame->data[0] = pYUV420P;
    pFrame->data[1] = pFrame->data[0] + width * height;
    pFrame->data[2] = pFrame->data[1] + (width * height) / 4;
    pFrame->pts = frameCounter;
    int got_picture = 0;
    if (!pCodecCtx) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return;
    }
    int ret = avcodec_encode_video2(pCodecCtx, &packet, pFrame, &got_picture);
    if(ret < 0) {
        NSLog(@"Failed to encode!");
    }
    if (got_picture == 1) {
        NSLog(@"Succeed to encode frame: %5d\tsize:%5d", frameCounter, packet.size);
        frameCounter++;
        av_free_packet(&packet);
    }
    free(pYUV420P);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void)teardown
{
    avcodec_close(pCodecCtx);
    av_free(pFrame);
    pCodecCtx = NULL;
    pFrame = NULL;
}

@end
