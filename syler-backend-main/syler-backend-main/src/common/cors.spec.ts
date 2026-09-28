import { isAllowedOrigin } from './cors';

describe('CORS allowlist', () => {
    const store = ['https://shop.example.com'];

    it('يسمح للمضيف المحلي والشبكة الخاصة ونطاق المتجر', () => {
        expect(isAllowedOrigin('http://localhost:54321', store)).toBe(true);
        expect(isAllowedOrigin('http://192.168.1.20:8080', store)).toBe(true);
        expect(isAllowedOrigin('https://shop.example.com', store)).toBe(true);
    });

    it('يرفض نطاقاً عاماً غير مذكور', () => {
        expect(isAllowedOrigin('https://evil.example', store)).toBe(false);
        expect(isAllowedOrigin('http://8.8.8.8', store)).toBe(false);
    });
});
