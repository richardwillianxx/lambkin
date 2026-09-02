import {
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Query,
  UseGuards,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuditService } from './audit.service';
import { AuditLogQueryDto } from './dto/audit-log-query.dto';

@Controller('admin/audit-logs')
@UseGuards(JwtAuthGuard)
export class AdminAuditController {
  constructor(private readonly auditService: AuditService) {}

  @Get()
  findAll(
    @CurrentUser()
    user: AccessTokenPayload,
    @Query()
    query: AuditLogQueryDto,
  ) {
    return this.auditService.findAll(user, query);
  }

  @Get(':id')
  findOne(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    auditLogId: number,
  ) {
    return this.auditService.findOne(user, auditLogId);
  }
}
