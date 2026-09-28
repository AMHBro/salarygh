import { Controller, Get, Post, Patch, Delete, Param, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { CategoriesService } from './categories.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { Permissions } from '../../common/decorators/permissions.decorator';

@ApiTags('Categories (M03)')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('categories')
export class CategoriesController {
    constructor(private readonly categoriesService: CategoriesService) { }

    @Post()
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'إنشاء تصنيف جديد (رئيسي أو فرعي)' })
    async create(@Body() dto: CreateCategoryDto) {
        const data = await this.categoriesService.create(dto);
        return { success: true, data };
    }

    @Get('tree')
    @ApiOperation({ summary: 'استرجاع شجرة التصنيفات الهرمية للواجهات' })
    async getTree() {
        const data = await this.categoriesService.getTree();
        return { success: true, data };
    }

    @Get()
    @ApiOperation({ summary: 'استرجاع قائمة التصنيفات المسطحة (للقوائم المنسدلة)' })
    async findAllFlat() {
        const data = await this.categoriesService.findAllFlat();
        return { success: true, data };
    }

    @Get(':id/breadcrumbs')
    @ApiOperation({ summary: 'استرجاع مسار التصنيف مع آبائه (Breadcrumbs)' })
    async getWithBreadcrumbs(@Param('id') id: string) {
        const result = await this.categoriesService.getWithBreadcrumbs(id);
        return { success: true, ...result };
    }

    @Patch(':id')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'تحديث بيانات التصنيف' })
    async update(@Param('id') id: string, @Body() dto: UpdateCategoryDto) {
        const data = await this.categoriesService.update(id, dto);
        return { success: true, data, message: 'تم تحديث التصنيف بنجاح' };
    }

    @Delete(':id')
    @Permissions('PRODUCT_EDIT')
    @ApiOperation({ summary: 'تعطيل التصنيف بعد التحقق من عدم وجود منتجات' })
    async remove(@Param('id') id: string) {
        const data = await this.categoriesService.remove(id);
        return { success: true, data, message: 'تم تعطيل التصنيف بنجاح' };
    }
}
