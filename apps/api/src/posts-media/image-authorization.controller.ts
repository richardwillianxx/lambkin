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
import { CurrentUser } from '../auth/current-user.decorator';
import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthorizeImageDto } from './dto/image-authorization.dto';
import { ImageAuthorizationService } from './image-authorization.service';

@Controller('image-authorizations')
@UseGuards(JwtAuthGuard)
export class ImageAuthorizationController {
  constructor(
    private readonly imageAuthorizationService: ImageAuthorizationService,
  ) {}

  @Post(':personId')
  authorize(
    @CurrentUser() user: AccessTokenPayload,
    @Param('personId', ParseIntPipe)
    personId: number,
    @Body() dto: AuthorizeImageDto,
  ) {
    return this.imageAuthorizationService.authorize(user, personId, dto);
  }

  @Get(':personId')
  findOne(
    @CurrentUser() user: AccessTokenPayload,
    @Param('personId', ParseIntPipe)
    personId: number,
  ) {
    return this.imageAuthorizationService.findOne(user, personId);
  }

  @Delete(':personId')
  revoke(
    @CurrentUser() user: AccessTokenPayload,
    @Param('personId', ParseIntPipe)
    personId: number,
  ) {
    return this.imageAuthorizationService.revoke(user, personId);
  }
}
