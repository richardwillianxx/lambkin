import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AdminAuditModule } from './admin-audit/admin-audit.module';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { PeopleUsersModule } from './people-users/people-users.module';
import { PostsMediaModule } from './posts-media/posts-media.module';
import { PrismaModule } from './prisma/prisma.module';
import { QuizzesRankingModule } from './quizzes-ranking/quizzes-ranking.module';
import { RecitativesModule } from './recitatives/recitatives.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env', '../../.env'],
    }),
    PrismaModule,
    AuthModule,
    PeopleUsersModule,
    PostsMediaModule,
    QuizzesRankingModule,
    RecitativesModule,
    AdminAuditModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule { }