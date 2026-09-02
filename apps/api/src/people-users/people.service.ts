import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma/prisma.service';
import { CreatePersonDto, UpdatePersonDto } from './dto/person.dto';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';
import { LinkGuardianDto } from './dto/guardian.dto';

@Injectable()
export class PeopleService {
  constructor(private readonly prisma: PrismaService) {}

  async createPerson(dto: CreatePersonDto) {
    await this.ensureActiveCongregation(dto.congregationId);

    await this.ensureUniquePersonFields(dto);

    return this.prisma.people.create({
      data: {
        congregation_id: dto.congregationId,
        role: dto.role,
        gender: dto.gender,
        full_name: dto.fullName,
        preferred_name: dto.preferredName,
        birth_date: new Date(dto.birthDate),
        email: dto.email ?? null,
        whatsapp: dto.whatsapp ?? null,
        street: dto.street ?? null,
        number: dto.number ?? null,
        complement: dto.complement ?? null,
        district: dto.district ?? null,
        city: dto.city ?? null,
        state: dto.state ?? null,
        zip_code: dto.zipCode ?? null,
        notes: dto.notes ?? null,
      },
    });
  }

  async findAll() {
    return this.prisma.people.findMany({
      orderBy: { full_name: 'asc' },
    });
  }

  async findOne(id: number) {
    const person = await this.prisma.people.findUnique({
      where: { id },
    });

    if (!person) {
      throw new NotFoundException('Pessoa não encontrada.');
    }

    const account = await this.prisma.users.findUnique({
      where: { person_id: id },
      select: {
        id: true,
        username: true,
        is_system_admin: true,
        email_verified_at: true,
        whatsapp_verified_at: true,
        status: true,
      },
    });

    const guardians = await this.prisma.person_guardians.findMany({
      where: { child_person_id: id },
    });

    return {
      ...person,
      account,
      guardians,
    };
  }

  async updatePerson(id: number, dto: UpdatePersonDto) {
    await this.ensurePersonExists(id);

    if (dto.congregationId !== undefined) {
      await this.ensureActiveCongregation(dto.congregationId);
    }

    await this.ensureUniquePersonFields(dto, id);

    return this.prisma.people.update({
      where: { id },
      data: {
        congregation_id: dto.congregationId,
        role: dto.role,
        gender: dto.gender,
        full_name: dto.fullName,
        preferred_name: dto.preferredName,
        birth_date: dto.birthDate ? new Date(dto.birthDate) : undefined,
        email: dto.email,
        whatsapp: dto.whatsapp,
        street: dto.street,
        number: dto.number,
        complement: dto.complement,
        district: dto.district,
        city: dto.city,
        state: dto.state,
        zip_code: dto.zipCode,
        notes: dto.notes,
      },
    });
  }

  async createAccount(personId: number, dto: CreateUserDto) {
    const person = await this.ensurePersonExists(personId);

    if (person.status !== 'A') {
      throw new BadRequestException(
        'Não é possível criar conta para uma pessoa inativa.',
      );
    }

    const existingAccount = await this.prisma.users.findUnique({
      where: { person_id: personId },
    });

    if (existingAccount) {
      throw new ConflictException('Esta pessoa já possui uma conta.');
    }

    const usernameExists = await this.prisma.users.findUnique({
      where: { username: dto.username },
    });

    if (usernameExists) {
      throw new ConflictException('Nome de usuário já está em uso.');
    }

    const age = this.calculateAge(person.birth_date);

    let verificationPersonId: number | null = null;

    if (age < 12) {
      const guardianLinks = await this.prisma.person_guardians.findMany({
        where: { child_person_id: personId },
      });

      if (guardianLinks.length === 0) {
        throw new BadRequestException(
          'Menores de 12 anos precisam possuir um responsável vinculado.',
        );
      }

      const guardianIds = guardianLinks.map((link) => link.guardian_person_id);

      const guardianAccounts = await this.prisma.users.findMany({
        where: {
          person_id: { in: guardianIds },
          status: 'A',
        },
        include: { person: true },
      });

      const guardianAccount = guardianAccounts.find(
        (account) => account.person.status === 'A',
      );

      if (!guardianAccount) {
        throw new BadRequestException(
          'Menores de 12 anos precisam possuir um responsável com conta ativa.',
        );
      }

      const guardian = guardianAccount.person;

      if (!person.email && !person.whatsapp) {
        if (!guardian.email && !guardian.whatsapp) {
          throw new BadRequestException(
            'A pessoa ou seu responsável precisa possuir e-mail ou WhatsApp para verificação.',
          );
        }

        verificationPersonId = guardian.id;
      }
    }

    if (age >= 12 && !person.email && !person.whatsapp) {
      throw new BadRequestException(
        'A pessoa precisa possuir e-mail ou WhatsApp para criar uma conta.',
      );
    }

    const passwordHash = await argon2.hash(dto.password, {
      type: argon2.argon2id,
    });

    return this.prisma.users.create({
      data: {
        person_id: personId,
        verification_person_id: verificationPersonId,
        username: dto.username,
        password_hash: passwordHash,
        is_system_admin: dto.isSystemAdmin ?? false,
        email_verified_at: null,
        whatsapp_verified_at: null,
        status: 'A',
      },
      select: {
        id: true,
        person_id: true,
        verification_person_id: true,
        username: true,
        is_system_admin: true,
        status: true,
        created_at: true,
      },
    });
  }

  async updateAccount(personId: number, dto: UpdateUserDto) {
    await this.ensurePersonExists(personId);

    const account = await this.prisma.users.findUnique({
      where: { person_id: personId },
    });

    if (!account) {
      throw new NotFoundException('Conta não encontrada.');
    }

    if (dto.username !== undefined) {
      const existing = await this.prisma.users.findUnique({
        where: { username: dto.username },
      });

      if (existing && existing.id !== account.id) {
        throw new ConflictException('Nome de usuário já está em uso.');
      }
    }

    return this.prisma.users.update({
      where: { id: account.id },
      data: {
        username: dto.username,
        is_system_admin: dto.isSystemAdmin,
      },
      select: {
        id: true,
        person_id: true,
        username: true,
        is_system_admin: true,
        status: true,
        updated_at: true,
      },
    });
  }

  async linkGuardian(childPersonId: number, dto: LinkGuardianDto) {
    if (childPersonId === dto.guardianPersonId) {
      throw new BadRequestException(
        'Uma pessoa não pode ser responsável por si mesma.',
      );
    }

    const child = await this.ensurePersonExists(childPersonId);
    const guardian = await this.ensurePersonExists(dto.guardianPersonId);

    if (child.status !== 'A' || guardian.status !== 'A') {
      throw new BadRequestException(
        'Pessoa e responsável precisam estar ativos.',
      );
    }

    const existing = await this.prisma.person_guardians.findFirst({
      where: {
        child_person_id: childPersonId,
        guardian_person_id: dto.guardianPersonId,
      },
    });

    if (existing) {
      throw new ConflictException(
        'Responsável já está vinculado a esta pessoa.',
      );
    }

    return this.prisma.person_guardians.create({
      data: {
        child_person_id: childPersonId,
        guardian_person_id: dto.guardianPersonId,
        relationship: dto.relationship,
      },
    });
  }

  async unlinkGuardian(childPersonId: number, guardianPersonId: number) {
    await this.ensurePersonExists(childPersonId);

    const link = await this.prisma.person_guardians.findFirst({
      where: {
        child_person_id: childPersonId,
        guardian_person_id: guardianPersonId,
      },
    });

    if (!link) {
      throw new NotFoundException('Vínculo de responsável não encontrado.');
    }

    await this.prisma.person_guardians.delete({
      where: { id: link.id },
    });

    return { message: 'Responsável desvinculado.' };
  }

  private async ensureActiveCongregation(congregationId: number) {
    const congregation = await this.prisma.congregations.findUnique({
      where: { id: congregationId },
    });

    if (!congregation || congregation.status !== 'A') {
      throw new BadRequestException('Congregação inválida ou inativa.');
    }
  }

  private async ensureUniquePersonFields(
    dto: {
      preferredName?: string;
      email?: string;
      whatsapp?: string;
    },
    currentPersonId?: number,
  ) {
    if (dto.preferredName !== undefined) {
      const existing = await this.prisma.people.findUnique({
        where: { preferred_name: dto.preferredName },
      });

      if (existing && existing.id !== currentPersonId) {
        throw new ConflictException('Nome preferido já está em uso.');
      }
    }

    if (dto.email !== undefined) {
      const existing = await this.prisma.people.findUnique({
        where: { email: dto.email },
      });

      if (existing && existing.id !== currentPersonId) {
        throw new ConflictException('E-mail já está em uso.');
      }
    }

    if (dto.whatsapp !== undefined) {
      const existing = await this.prisma.people.findUnique({
        where: { whatsapp: dto.whatsapp },
      });

      if (existing && existing.id !== currentPersonId) {
        throw new ConflictException('WhatsApp já está em uso.');
      }
    }
  }

  private async ensurePersonExists(id: number) {
    const person = await this.prisma.people.findUnique({
      where: { id },
    });

    if (!person) {
      throw new NotFoundException('Pessoa não encontrada.');
    }

    return person;
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
