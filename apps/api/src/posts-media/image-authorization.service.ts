import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { AuthorizeImageDto } from './dto/image-authorization.dto';

@Injectable()
export class ImageAuthorizationService {
  constructor(private readonly prisma: PrismaService) {}

  async authorize(
    user: AccessTokenPayload,
    personId: number,
    dto: AuthorizeImageDto,
  ) {
    const person = await this.ensurePersonExists(personId);

    await this.ensureCanAuthorize(user, personId, person.birth_date);

    const existing = await this.prisma.image_authorizations.findUnique({
      where: {
        person_id: personId,
      },
    });

    if (existing) {
      return this.prisma.image_authorizations.update({
        where: {
          id: existing.id,
        },
        data: {
          authorized_by_person_id: user.personId,
          terms_version: dto.termsVersion,
          accepted_at: new Date(),
          status: 'A',
        },
      });
    }

    return this.prisma.image_authorizations.create({
      data: {
        person_id: personId,
        authorized_by_person_id: user.personId,
        terms_version: dto.termsVersion,
        accepted_at: new Date(),
        status: 'A',
      },
    });
  }

  async findOne(user: AccessTokenPayload, personId: number) {
    const person = await this.ensurePersonExists(personId);

    await this.ensureCanView(user, personId, person.birth_date);

    const authorization = await this.prisma.image_authorizations.findUnique({
      where: {
        person_id: personId,
      },
    });

    if (!authorization) {
      throw new NotFoundException('Autorização de imagem não encontrada.');
    }

    return authorization;
  }

  async revoke(user: AccessTokenPayload, personId: number) {
    const person = await this.ensurePersonExists(personId);

    await this.ensureCanAuthorize(user, personId, person.birth_date);

    const authorization = await this.prisma.image_authorizations.findUnique({
      where: {
        person_id: personId,
      },
    });

    if (!authorization || authorization.status !== 'A') {
      throw new NotFoundException(
        'Autorização de imagem ativa não encontrada.',
      );
    }

    await this.prisma.image_authorizations.update({
      where: {
        id: authorization.id,
      },
      data: {
        status: 'I',
      },
    });

    return {
      message: 'Autorização de imagem revogada.',
    };
  }

  private async ensurePersonExists(personId: number) {
    const person = await this.prisma.people.findUnique({
      where: {
        id: personId,
      },
    });

    if (!person || person.status !== 'A') {
      throw new NotFoundException('Pessoa não encontrada.');
    }

    return person;
  }

  private async ensureCanAuthorize(
    user: AccessTokenPayload,
    personId: number,
    birthDate: Date,
  ) {
    const age = this.calculateAge(birthDate);

    if (age >= 12) {
      if (user.personId !== personId) {
        throw new ForbiddenException(
          'Somente a própria pessoa pode autorizar o uso de sua imagem.',
        );
      }

      return;
    }

    const guardian = await this.prisma.person_guardians.findFirst({
      where: {
        child_person_id: personId,
        guardian_person_id: user.personId,
      },
    });

    if (!guardian) {
      throw new ForbiddenException(
        'Somente um responsável vinculado pode autorizar o uso da imagem do menor.',
      );
    }
  }

  private async ensureCanView(
    user: AccessTokenPayload,
    personId: number,
    birthDate: Date,
  ) {
    if (user.isSystemAdmin) {
      return;
    }

    if (user.personId === personId) {
      return;
    }

    const age = this.calculateAge(birthDate);

    if (age < 12) {
      const guardian = await this.prisma.person_guardians.findFirst({
        where: {
          child_person_id: personId,
          guardian_person_id: user.personId,
        },
      });

      if (guardian) {
        return;
      }
    }

    throw new ForbiddenException(
      'Usuário sem permissão para consultar esta autorização.',
    );
  }

  private calculateAge(birthDate: Date): number {
    const today = new Date();

    let age = today.getFullYear() - birthDate.getFullYear();

    const monthDifference = today.getMonth() - birthDate.getMonth();

    if (
      monthDifference < 0 ||
      (monthDifference === 0 && today.getDate() < birthDate.getDate())
    ) {
      age--;
    }

    return age;
  }
}
