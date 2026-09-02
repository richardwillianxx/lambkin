import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SubmitQuizAttemptDto } from './dto/attempt.dto';
import {
  CreateQuizDto,
  UpdateQuizDto,
  UpdateQuizStateDto,
} from './dto/quiz.dto';
import { UpdateQuizStructureDto } from './dto/quiz-structure.dto';
import { QuizAttemptsService } from './quiz-attempts.service';
import { QuizStructureService } from './quiz-structure.service';
import { QuizzesService } from './quizzes.service';

@Controller('quizzes')
@UseGuards(JwtAuthGuard)
export class QuizzesController {
  constructor(
    private readonly quizzesService: QuizzesService,
    private readonly quizStructureService: QuizStructureService,
    private readonly quizAttemptsService: QuizAttemptsService,
  ) {}

  @Post()
  create(
    @CurrentUser()
    user: AccessTokenPayload,
    @Body()
    dto: CreateQuizDto,
  ) {
    return this.quizzesService.create(user, dto);
  }

  @Get()
  findAll(
    @CurrentUser()
    user: AccessTokenPayload,
  ) {
    return this.quizzesService.findAll(user);
  }

  @Get(':id/my-attempts')
  getMyAttempts(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
  ) {
    return this.quizAttemptsService.getMyAttempts(user, quizId);
  }

  @Get(':id/ranking')
  getRanking(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
    @Query('congregationId')
    congregationId?: string,
  ) {
    const parsedCongregationId =
      this.parseOptionalCongregationId(congregationId);

    return this.quizAttemptsService.getRanking(
      user,
      quizId,
      parsedCongregationId,
    );
  }

  @Get(':id')
  findOne(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
  ) {
    return this.quizzesService.findOne(user, quizId);
  }

  @Patch(':id')
  update(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
    @Body()
    dto: UpdateQuizDto,
  ) {
    return this.quizzesService.update(user, quizId, dto);
  }

  @Put(':id/structure')
  updateStructure(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
    @Body()
    dto: UpdateQuizStructureDto,
  ) {
    return this.quizStructureService.updateStructure(user, quizId, dto);
  }

  @Patch(':id/state')
  updateState(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
    @Body()
    dto: UpdateQuizStateDto,
  ) {
    return this.quizStructureService.updateState(user, quizId, dto);
  }

  @Post(':id/attempts')
  submitAttempt(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
    @Body()
    dto: SubmitQuizAttemptDto,
  ) {
    return this.quizAttemptsService.submitAttempt(user, quizId, dto);
  }

  @Delete(':id')
  remove(
    @CurrentUser()
    user: AccessTokenPayload,
    @Param('id', ParseIntPipe)
    quizId: number,
  ) {
    return this.quizzesService.remove(user, quizId);
  }

  private parseOptionalCongregationId(value?: string) {
    if (value === undefined) {
      return undefined;
    }

    const parsedValue = Number(value);

    if (!Number.isInteger(parsedValue) || parsedValue < 1) {
      throw new BadRequestException(
        'congregationId deve ser um número inteiro positivo.',
      );
    }

    return parsedValue;
  }
}
