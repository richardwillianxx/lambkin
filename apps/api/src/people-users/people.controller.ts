import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { LinkGuardianDto } from './dto/guardian.dto';
import {
  CreatePersonDto,
  UpdatePersonDto,
} from './dto/person.dto';
import {
  CreateUserDto,
  UpdateUserDto,
} from './dto/user.dto';
import { PeopleService } from './people.service';

@Controller('people')
@UseGuards(JwtAuthGuard)
export class PeopleController {
  constructor(
    private readonly peopleService: PeopleService,
  ) { }

  @Post()
  create(
    @CurrentUser() user: AccessTokenPayload,
    @Body() dto: CreatePersonDto,
  ) {
    this.ensureSystemAdmin(user);

    return this.peopleService.createPerson(dto);
  }

  @Get()
  findAll() {
    return this.peopleService.findAll();
  }

  @Get(':id')
  findOne(
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.peopleService.findOne(id);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdatePersonDto,
  ) {
    this.ensureSystemAdmin(user);

    return this.peopleService.updatePerson(
      id,
      dto,
    );
  }

  @Post(':id/account')
  createAccount(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CreateUserDto,
  ) {
    this.ensureSystemAdmin(user);

    return this.peopleService.createAccount(
      id,
      dto,
    );
  }

  @Patch(':id/account')
  updateAccount(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    this.ensureSystemAdmin(user);

    return this.peopleService.updateAccount(
      id,
      dto,
    );
  }

  @Post(':id/guardians')
  linkGuardian(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: LinkGuardianDto,
  ) {
    this.ensureSystemAdmin(user);

    return this.peopleService.linkGuardian(
      id,
      dto,
    );
  }

  @Delete(':id/guardians/:guardianId')
  unlinkGuardian(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    id: number,
    @Param(
      'guardianId',
      ParseIntPipe,
    )
    guardianId: number,
  ) {
    this.ensureSystemAdmin(user);

    return this.peopleService.unlinkGuardian(
      id,
      guardianId,
    );
  }

  private ensureSystemAdmin(
    user: AccessTokenPayload,
  ) {
    if (!user.isSystemAdmin) {
      throw new ForbiddenException(
        'Acesso permitido somente para administrador.',
      );
    }
  }
}