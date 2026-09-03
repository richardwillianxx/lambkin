import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  ConfirmMediaUploadDto,
  CreateMediaUploadUrlDto,
} from './dto/media.dto';
import { MediaService } from './media.service';

@Controller('media')
@UseGuards(JwtAuthGuard)
export class MediaController {
  constructor(private readonly mediaService: MediaService) {}

  @Post('upload-url')
  createUploadUrl(
    @CurrentUser()
    user: AccessTokenPayload,
    @Body()
    dto: CreateMediaUploadUrlDto,
  ) {
    return this.mediaService.createUploadUrl(user, dto);
  }

  @Post('confirm')
  confirmUpload(
    @CurrentUser()
    user: AccessTokenPayload,
    @Body()
    dto: ConfirmMediaUploadDto,
  ) {
    return this.mediaService.confirmUpload(user, dto);
  }

  @Get(':id/access')
  getAccessUrl(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    mediaId: number,
  ) {
    return this.mediaService.getAccessUrl(user, mediaId);
  }

  @Delete(':id')
  remove(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    mediaId: number,
  ) {
    return this.mediaService.remove(user, mediaId);
  }
}
