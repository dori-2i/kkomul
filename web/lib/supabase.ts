import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// 웹 페이지에 공개되어도 되는 값만 씀 (RLS로 읽기 권한을 제한함)
// 값은 web/.env.local 파일에 적어 둠 (GitHub에 올라가지 않음)
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

let client: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (!url || !key) {
    throw new Error(
      "Supabase 주소나 공개 키가 없어요. web/.env.local 파일에 NEXT_PUBLIC_SUPABASE_URL과 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY를 적어 주세요.",
    );
  }
  client ??= createClient(url, key, { auth: { persistSession: false } });
  return client;
}
