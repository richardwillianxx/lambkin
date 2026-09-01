import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PeopleUsersModule } from './people-users/people-users.module';
import { PostsMediaModule } from './posts-media/posts-media.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    PrismaModule,
    AuthModule,
    PeopleUsersModule,
    PostsMediaModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule { }