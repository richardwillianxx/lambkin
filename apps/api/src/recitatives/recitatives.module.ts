import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RecitativesController } from './recitatives.controller';
import { RecitativesService } from './recitatives.service';

@Module({
  imports: [
    AuthModule,
  ],
  controllers: [
    RecitativesController,
  ],
  providers: [
    RecitativesService,
  ],
})
export class RecitativesModule {}