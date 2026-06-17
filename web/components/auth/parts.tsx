type FieldProps = {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  placeholder?: string;
  autoComplete?: string;
  required?: boolean;
  minLength?: number;
};

export function Field({ label, value, onChange, type = "text", ...rest }: FieldProps) {
  return (
    <label className="block">
      <span className="text-xs font-medium text-neutral-400">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        {...rest}
        className="mt-1 w-full bg-ink/60 border border-line rounded-lg px-3 py-2.5 text-sm text-neutral-100 placeholder:text-neutral-600 focus:outline-none focus:border-reddit/60 focus:ring-2 focus:ring-reddit/15"
      />
    </label>
  );
}

export function Alert({ kind, children }: { kind: "error" | "success" | "info"; children: React.ReactNode }) {
  const c =
    kind === "error"
      ? "bg-bear/10 text-bear ring-bear/20"
      : kind === "success"
      ? "bg-bull/10 text-bull ring-bull/20"
      : "bg-white/5 text-neutral-300 ring-white/10";
  return <div className={`text-sm rounded-lg px-3 py-2 leading-relaxed ring-1 ring-inset ${c}`}>{children}</div>;
}

export function Divider({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3">
      <span className="h-px flex-1 bg-line" />
      <span className="text-xs text-neutral-600">{children}</span>
      <span className="h-px flex-1 bg-line" />
    </div>
  );
}

export function GoogleLogo() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden>
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.27-4.74 3.27-8.1z" />
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A11 11 0 0 0 12 23z" />
      <path fill="#FBBC05" d="M5.84 14.1a6.6 6.6 0 0 1 0-4.2V7.06H2.18a11 11 0 0 0 0 9.88l3.66-2.84z" />
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84C6.71 7.31 9.14 5.38 12 5.38z" />
    </svg>
  );
}

export function AppleLogo() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden className="-mt-0.5">
      <path d="M16.365 1.43c0 1.14-.42 2.2-1.12 3-.78.88-2.06 1.56-3.13 1.47-.13-1.1.43-2.27 1.07-2.98.72-.81 2.02-1.42 3.18-1.49zM20.8 17.1c-.5 1.16-.74 1.68-1.39 2.71-.91 1.44-2.19 3.23-3.78 3.24-1.41.01-1.78-.92-3.69-.91-1.91.01-2.31.93-3.72.91-1.59-.01-2.8-1.63-3.71-3.07-2.55-4.03-2.82-8.76-1.25-11.27 1.12-1.79 2.88-2.84 4.54-2.84 1.69 0 2.75.93 4.15.93 1.36 0 2.18-.93 4.14-.93 1.48 0 3.05.81 4.17 2.2-3.66 2-3.07 7.23.24 9.13z" />
    </svg>
  );
}
