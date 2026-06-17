"use client";

import { createContext, useContext, useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { supabase, isAuthConfigured } from "@/lib/supabase";
import { isAdminEmail } from "@/lib/admin";
import { setTrackingDisabled } from "@/lib/analytics";

type AuthState = {
  user: User | null;
  loading: boolean;
  configured: boolean;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState>({
  user: null,
  loading: true,
  configured: false,
  signOut: async () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }
    let active = true;
    // 登录为管理员（=自己）时，自动把本设备标记为「不记录」，从而排除自有访问。
    // 只自动「开启」、不自动关闭——清除需在数据看板里手动切换。
    const apply = (u: User | null) => {
      setUser(u);
      if (u && isAdminEmail(u.email)) setTrackingDisabled(true);
    };
    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      apply(data.session?.user ?? null);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      apply(session?.user ?? null);
      setLoading(false);
    });
    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  const signOut = async () => {
    if (supabase) await supabase.auth.signOut();
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, loading, configured: isAuthConfigured, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
