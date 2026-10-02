import { ConflictException } from '@nestjs/common';
import { RepresentativeVisitsService } from './representative-visits.service';

describe('زيارات المندوب', () => {
    const visitId = '66666666-6666-6666-6666-666666666666';

    function service() {
        const visits = new Map<string, any>();
        const prisma = {
            representatives: {
                findUnique: async () => ({ id: 'rep-1' }),
            },
            representative_visits: {
                create: async ({ data }: any) => {
                    const visit = {
                        id: visitId,
                        started_at: new Date('2026-10-02T07:00:00.000Z'),
                        ended_at: null,
                        postponed_until: null,
                        latitude: data.latitude,
                        longitude: data.longitude,
                        geofence_radius_m: data.geofence_radius_m,
                        customer_id: data.customer_id,
                        status: data.status,
                        notes: data.notes,
                    };
                    visits.set(visit.id, visit);
                    return visit;
                },
                findFirst: async ({ where }: any) => visits.get(where.id) ?? null,
                update: async ({ where, data }: any) => {
                    const current = visits.get(where.id);
                    const next = { ...current, ...data };
                    visits.set(where.id, next);
                    return next;
                },
            },
        };
        return { visits: new RepresentativeVisitsService(prisma as any), store: visits };
    }

    it('يبدأ زيارة بمعرّف من قاعدة البيانات لا ببادئة vis_', async () => {
        const { visits } = service();
        const created = await visits.start('user-1', {
            customer_id: 'cust-1',
            latitude: 33.31,
            longitude: 44.36,
        });
        expect(created.id).toBe(visitId);
        expect(created.id.startsWith('vis_')).toBe(false);
        expect(created.status).toBe('in_progress');
        expect(created.geofence.latitude).toBe(33.31);
        expect(created.geofence.radius_meters).toBe(150);
    });

    it('ينهي الزيارة ويرفض إنهاؤها مرة ثانية', async () => {
        const { visits } = service();
        await visits.start('user-1', { customer_id: 'cust-1' });
        const ended = await visits.end('user-1', { visit_id: visitId, notes: 'تم' });
        expect(ended.status).toBe('completed');
        expect(ended.ended_at).toBeInstanceOf(Date);
        await expect(visits.end('user-1', { visit_id: visitId })).rejects.toBeInstanceOf(ConflictException);
    });

    it('يؤجل الزيارة المفتوحة', async () => {
        const { visits } = service();
        await visits.start('user-1', { customer_id: 'cust-1' });
        const postponed = await visits.postpone('user-1', {
            visit_id: visitId,
            postponed_until: '2026-10-03T00:00:00.000Z',
        });
        expect(postponed.status).toBe('postponed');
        expect(postponed.postponed_until).toEqual(new Date('2026-10-03T00:00:00.000Z'));
    });
});
