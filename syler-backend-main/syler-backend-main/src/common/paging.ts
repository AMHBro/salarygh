/** صفحة ثابتة السقف حتى لا يطلب عميل كل الجدول دفعة واحدة. */
export function pageWindow(
  query: { page?: number | string; limit?: number | string },
  fallback = 20,
  max = 100,
) {
  const page = Math.max(1, Number(query.page) || 1);
  const limit = Math.min(max, Math.max(1, Number(query.limit) || fallback));
  return { page, limit, skip: (page - 1) * limit };
}
