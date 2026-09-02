import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CreateRecitativeDto,
  UpdateRecitativeDto,
} from './dto/recitative.dto';
import { RecitativesService } from './recitatives.service';

@Controller('recitatives')
@UseGuards(JwtAuthGuard)
export class RecitativesController {
  constructor(
    private readonly recitativesService:
      RecitativesService,
  ) {}

  @Post()
  create(
    @CurrentUser()
    user: AccessTokenPayload,
    @Body()
    dto: CreateRecitativeDto,
  ) {
    return this.recitativesService.create(
      user,
      dto,
    );
  }

  @Get()
  findAll(
    @CurrentUser()
    user: AccessTokenPayload,
  ) {
    return this.recitativesService.findAll(
      user,
    );
  }

  @Get(':id')
  findOne(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param(
      'id',
      ParseIntPipe,
    )
    recitativeId: number,
  ) {
    return this.recitativesService.findOne(
      user,
      recitativeId,
    );
  }

  @Patch(':id')
  update(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param(
      'id',
      ParseIntPipe,
    )
    recitativeId: number,
    @Body()
    dto: UpdateRecitativeDto,
  ) {
    return this.recitativesService.update(
      user,
      recitativeId,
      dto,
    );
  }

  @Delete(':id')
  remove(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param(
      'id',
      ParseIntPipe,
    )
    recitativeId: number,
  ) {
    return this.recitativesService.remove(
      user,
      recitativeId,
    );
  }
}