import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { CreateRecitativeDto, UpdateRecitativeDto } from './dto/recitative.dto';

@Injectable()
export class RecitativesService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AccessTokenPayload, dto: CreateRecitativeDto) {
    const congregationId = await this.resolveCongregationForCreate(
      user,
      dto.congregationId,
    );

    const recitativeDate = this.parseDate(dto.recitativeDate);

    return this.prisma.recitatives.create({
      data: {
        name: dto.name,
        group_number: dto.groupNumber,
        bible_book: dto.bibleBook,
        bible_chapter: dto.bibleChapter,
        bible_verse: dto.bibleVerse,
        gender: dto.gender,
        congregation_id: congregationId,
        created_by_user_id: user.sub,
        recitative_date: recitativeDate,
        after_text: dto.afterText ?? null,
        reciters_count: dto.recitersCount ?? null,
        status: 'A',
      },
    });
  }

  async findAll(user: AccessTokenPayload) {
    const congregationId = await this.getViewCongregation(user);

    return this.prisma.recitatives.findMany({
      where: {
        status: 'A',
        ...(congregationId !== null
          ? {
              congregation_id: congregationId,
            }
          : {}),
      },
      select: {
        id: true,
        name: true,
        group_number: true,
        bible_book: true,
        bible_chapter: true,
        bible_verse: true,
        gender: true,
        congregation_id: true,
        created_by_user_id: true,
        recitative_date: true,
        after_text: true,
        reciters_count: true,
        created_at: true,
        updated_at: true,
        congregations: {
          select: {
            id: true,
            name: true,
          },
        },
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
      orderBy: [
        {
          recitative_date: 'desc',
        },
        {
          id: 'desc',
        },
      ],
    });
  }

  async findOne(user: AccessTokenPayload, recitativeId: number) {
    const recitative = await this.getRecitativeOrThrow(recitativeId);

    await this.ensureCanView(user, recitative.congregation_id);

    return this.prisma.recitatives.findUnique({
      where: {
        id: recitativeId,
      },
      select: {
        id: true,
        name: true,
        group_number: true,
        bible_book: true,
        bible_chapter: true,
        bible_verse: true,
        gender: true,
        congregation_id: true,
        created_by_user_id: true,
        recitative_date: true,
        after_text: true,
        reciters_count: true,
        created_at: true,
        updated_at: true,
        congregations: {
          select: {
            id: true,
            name: true,
          },
        },
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
    });
  }

  async update(
    user: AccessTokenPayload,
    recitativeId: number,
    dto: UpdateRecitativeDto,
  ) {
    const recitative = await this.getRecitativeOrThrow(recitativeId);

    this.ensureCanManage(user, recitative.created_by_user_id);

    return this.prisma.recitatives.update({
      where: {
        id: recitativeId,
      },
      data: {
        name: dto.name,
        group_number: dto.groupNumber,
        bible_book: dto.bibleBook,
        bible_chapter: dto.bibleChapter,
        bible_verse: dto.bibleVerse,
        gender: dto.gender,
        recitative_date:
          dto.recitativeDate !== undefined
            ? this.parseDate(dto.recitativeDate)
            : undefined,
        after_text: dto.afterText,
        reciters_count: dto.recitersCount,
      },
    });
  }

  async remove(user: AccessTokenPayload, recitativeId: number) {
    const recitative = await this.getRecitativeOrThrow(recitativeId);

    this.ensureCanManage(user, recitative.created_by_user_id);

    await this.prisma.recitatives.update({
      where: {
        id: recitativeId,
      },
      data: {
        status: 'I',
      },
    });

    return {
      message: 'Recitativo removido.',
    };
  }

  private async getRecitativeOrThrow(recitativeId: number) {
    const recitative = await this.prisma.recitatives.findFirst({
      where: {
        id: recitativeId,
        status: 'A',
      },
    });

    if (!recitative) {
      throw new NotFoundException('Recitativo não encontrado.');
    }

    return recitative;
  }

  private async resolveCongregationForCreate(
    user: AccessTokenPayload,
    requestedCongregationId?: number,
  ) {
    if (user.isSystemAdmin) {
      if (requestedCongregationId === undefined) {
        throw new BadRequestException(
          'System Admin deve informar congregationId.',
        );
      }

      await this.ensureActiveCongregation(requestedCongregationId);

      return requestedCongregationId;
    }

    const account = await this.getActiveAccount(user.sub);

    if (account.person.role !== 'ASSISTANT') {
      throw new ForbiddenException(
        'Usuário sem permissão para cadastrar recitativos.',
      );
    }

    const congregationId = account.person.congregation_id;

    if (!congregationId) {
      throw new BadRequestException(
        'A pessoa precisa pertencer a uma congregação.',
      );
    }

    await this.ensureActiveCongregation(congregationId);

    if (
      requestedCongregationId !== undefined &&
      requestedCongregationId !== congregationId
    ) {
      throw new ForbiddenException(
        'Usuário não pode cadastrar recitativos para outra congregação.',
      );
    }

    return congregationId;
  }

  private async getViewCongregation(user: AccessTokenPayload) {
    if (user.isSystemAdmin) {
      return null;
    }

    const account = await this.getActiveAccount(user.sub);

    const congregationId = account.person.congregation_id;

    if (!congregationId) {
      throw new BadRequestException(
        'A pessoa precisa pertencer a uma congregação.',
      );
    }

    return congregationId;
  }

  private async ensureCanView(
    user: AccessTokenPayload,
    congregationId: number,
  ) {
    if (user.isSystemAdmin) {
      return;
    }

    const account = await this.getActiveAccount(user.sub);

    if (account.person.congregation_id !== congregationId) {
      throw new ForbiddenException(
        'Usuário sem permissão para consultar este recitativo.',
      );
    }
  }

  private ensureCanManage(user: AccessTokenPayload, createdByUserId: number) {
    if (user.isSystemAdmin) {
      return;
    }

    if (user.sub !== createdByUserId) {
      throw new ForbiddenException(
        'Usuário sem permissão para alterar este recitativo.',
      );
    }
  }

  private async getActiveAccount(userId: number) {
    const account = await this.prisma.users.findUnique({
      where: {
        id: userId,
      },
      select: {
        status: true,
        person: {
          select: {
            status: true,
            role: true,
            congregation_id: true,
          },
        },
      },
    });

    if (!account || account.status !== 'A' || account.person.status !== 'A') {
      throw new ForbiddenException('Usuário inválido ou inativo.');
    }

    return account;
  }

  private async ensureActiveCongregation(congregationId: number) {
    const congregation = await this.prisma.congregations.findUnique({
      where: {
        id: congregationId,
      },
    });

    if (!congregation || congregation.status !== 'A') {
      throw new BadRequestException('Congregação inválida ou inativa.');
    }
  }

  private parseDate(value: string) {
    const parts = value.split('-');

    const year = Number(parts[0]);

    const month = Number(parts[1]);

    const day = Number(parts[2]);

    const date = new Date(Date.UTC(year, month - 1, day));

    if (
      date.getUTCFullYear() !== year ||
      date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day
    ) {
      throw new BadRequestException('Data do recitativo inválida.');
    }

    return date;
  }
}
