import { NestFactory } from '@nestjs/core';
import { json, urlencoded } from 'express';
import { AppModule } from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { PrismaClientExceptionFilter } from './common/filters/prisma-client-exception.filter';
import { allowedOriginsFromEnv, isAllowedOrigin } from './common/cors';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  app.use(json({ limit: '4mb' }));
  app.use(urlencoded({ extended: true, limit: '4mb' }));
  const extraOrigins = allowedOriginsFromEnv(process.env.CORS_ORIGINS);
  app.enableCors({
    origin: (
      origin: string | undefined,
      callback: (err: Error | null, allow?: boolean) => void,
    ) => {
      if (!origin || isAllowedOrigin(origin, extraOrigins)) {
        callback(null, true);
        return;
      }
      callback(null, false);
    },
    credentials: true,
  });

  app.setGlobalPrefix('api/v1');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  // تسجيل الفلتر العام لتحويل أخطاء Prisma إلى استجابات HTTP واضحة
  app.useGlobalFilters(new PrismaClientExceptionFilter());

  const config = new DocumentBuilder()
    .setTitle('Sayler Sales System API')
    .setDescription('وثائق واجهة برمجة التطبيقات لنظام المبيعات والمخازن')
    .setVersion('1.0')
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/docs', app, document);

  const port = Number(process.env.PORT || 3000);
  const host = process.env.HOST || '0.0.0.0';
  await app.listen(port, host);

  console.log(`Server running on: http://localhost:${port}/api/v1`);
  console.log(`LAN clients: http://<this-pc-lan-ip>:${port}/api/v1`);
  console.log(`Swagger Docs: http://localhost:${port}/api/docs`);
}
bootstrap();
