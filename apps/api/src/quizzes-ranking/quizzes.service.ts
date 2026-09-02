import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateQuizDto,
  UpdateQuizDto,
} from './dto/quiz.dto';

@Injectable()
export class QuizzesService {
  constructor(
    private readonly prisma: PrismaService,
  ) {}

  async create(
    user: AccessTokenPayload,
    dto: CreateQuizDto,
  ) {
    await this.ensureCanCreateQuiz(user);

    return this.prisma.quizzes.create({
      data: {
        title: dto.title,
        description:
          dto.description ?? null,
        quiz_state: 'DRAFT',
        max_attempts:
          dto.maxAttempts,
        created_by_user_id:
          user.sub,
        status: 'A',
      },
    });
  }

  async findAll(
    user: AccessTokenPayload,
  ) {
    if (user.isSystemAdmin) {
      return this.prisma.quizzes.findMany({
        where: {
          status: 'A',
        },
        select: {
          id: true,
          title: true,
          description: true,
          quiz_state: true,
          max_attempts: true,
          created_by_user_id: true,
          created_at: true,
          updated_at: true,
          users: {
            select: {
              id: true,
              username: true,
              person: {
                select: {
                  id: true,
                  full_name: true,
                  preferred_name: true,
                  role: true,
                },
              },
            },
          },
        },
        orderBy: {
          created_at: 'desc',
        },
      });
    }

    return this.prisma.quizzes.findMany({
      where: {
        status: 'A',
        OR: [
          {
            quiz_state: 'ACTIVE',
          },
          {
            quiz_state: 'CLOSED',
          },
          {
            created_by_user_id:
              user.sub,
          },
        ],
      },
      select: {
        id: true,
        title: true,
        description: true,
        quiz_state: true,
        max_attempts: true,
        created_by_user_id: true,
        created_at: true,
        updated_at: true,
        users: {
          select: {
            id: true,
            username: true,
            person: {
              select: {
                id: true,
                full_name: true,
                preferred_name: true,
                role: true,
              },
            },
          },
        },
      },
      orderBy: {
        created_at: 'desc',
      },
    });
  }

  async findOne(
    user: AccessTokenPayload,
    quizId: number,
  ) {
    const quiz =
      await this.getQuizOrThrow(
        quizId,
      );

    if (
      quiz.quiz_state === 'DRAFT'
    ) {
      await this.ensureCanManageQuiz(
        user,
        quiz.created_by_user_id,
      );

      return this.prisma.quizzes.findUnique({
        where: {
          id: quizId,
        },
        select: {
          id: true,
          title: true,
          description: true,
          quiz_state: true,
          max_attempts: true,
          created_by_user_id: true,
          created_at: true,
          updated_at: true,
          quiz_questions: {
            where: {
              status: 'A',
            },
            orderBy: {
              position: 'asc',
            },
            select: {
              id: true,
              question_text: true,
              points: true,
              position: true,
              quiz_options: {
                where: {
                  status: 'A',
                },
                orderBy: {
                  position: 'asc',
                },
                select: {
                  id: true,
                  option_text: true,
                  is_correct: true,
                  position: true,
                },
              },
            },
          },
        },
      });
    }

    return this.prisma.quizzes.findUnique({
      where: {
        id: quizId,
      },
      select: {
        id: true,
        title: true,
        description: true,
        quiz_state: true,
        max_attempts: true,
        created_by_user_id: true,
        created_at: true,
        updated_at: true,
        quiz_questions: {
          where: {
            status: 'A',
          },
          orderBy: {
            position: 'asc',
          },
          select: {
            id: true,
            question_text: true,
            points: true,
            position: true,
            quiz_options: {
              where: {
                status: 'A',
              },
              orderBy: {
                position: 'asc',
              },
              select: {
                id: true,
                option_text: true,
                position: true,
              },
            },
          },
        },
      },
    });
  }

  async update(
    user: AccessTokenPayload,
    quizId: number,
    dto: UpdateQuizDto,
  ) {
    const quiz =
      await this.getQuizOrThrow(
        quizId,
      );

    await this.ensureCanManageQuiz(
      user,
      quiz.created_by_user_id,
    );

    this.ensureQuizIsDraft(
      quiz.quiz_state,
    );

    return this.prisma.quizzes.update({
      where: {
        id: quizId,
      },
      data: {
        title: dto.title,
        description:
          dto.description,
        max_attempts:
          dto.maxAttempts,
      },
    });
  }

  async remove(
    user: AccessTokenPayload,
    quizId: number,
  ) {
    const quiz =
      await this.getQuizOrThrow(
        quizId,
      );

    await this.ensureCanManageQuiz(
      user,
      quiz.created_by_user_id,
    );

    this.ensureQuizIsDraft(
      quiz.quiz_state,
    );

    await this.prisma.quizzes.update({
      where: {
        id: quizId,
      },
      data: {
        status: 'I',
      },
    });

    return {
      message: 'Quiz removido.',
    };
  }

  async getQuizOrThrow(
    quizId: number,
  ) {
    const quiz =
      await this.prisma.quizzes.findFirst({
        where: {
          id: quizId,
          status: 'A',
        },
      });

    if (!quiz) {
      throw new NotFoundException(
        'Quiz não encontrado.',
      );
    }

    return quiz;
  }

  async ensureCanCreateQuiz(
    user: AccessTokenPayload,
  ) {
    if (user.isSystemAdmin) {
      return;
    }

    const account =
      await this.prisma.users.findUnique({
        where: {
          id: user.sub,
        },
        select: {
          status: true,
          person: {
            select: {
              status: true,
              role: true,
            },
          },
        },
      });

    if (
      !account ||
      account.status !== 'A' ||
      account.person.status !== 'A'
    ) {
      throw new ForbiddenException(
        'Usuário sem permissão para criar quizzes.',
      );
    }

    const allowedRoles = [
      'MINISTRY',
      'ASSISTANT',
    ];

    if (
      !allowedRoles.includes(
        account.person.role,
      )
    ) {
      throw new ForbiddenException(
        'Usuário sem permissão para criar quizzes.',
      );
    }
  }

  async ensureCanManageQuiz(
    user: AccessTokenPayload,
    createdByUserId: number,
  ) {
    if (user.isSystemAdmin) {
      return;
    }

    if (
      user.sub !== createdByUserId
    ) {
      throw new ForbiddenException(
        'Usuário sem permissão para alterar este quiz.',
      );
    }

    await this.ensureCanCreateQuiz(
      user,
    );
  }

  ensureQuizIsDraft(
    quizState: string,
  ) {
    if (quizState !== 'DRAFT') {
      throw new BadRequestException(
        'O quiz só pode ser alterado enquanto estiver em rascunho.',
      );
    }
  }
}