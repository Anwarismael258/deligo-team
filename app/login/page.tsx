"use client";

import { FormEvent, useState } from "react";

export default function LoginPage() {
  const [showPassword, setShowPassword] = useState(false);
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(false);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true); setNotice("");
    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email: form.get("email"), password: form.get("password") }) });
    const result = await response.json() as { error?: string };
    if (!response.ok) { setNotice(result.error || "Não foi possível entrar."); setLoading(false); return; }
    window.location.assign("/");
  };

  return (
    <main className="loginPage">
      <section className="loginBrandPanel">
        <div className="loginBrand">
          <img src="/deligo-icon.png" alt="Símbolo DeliGo Triunfal" />
          <div><strong>DELIGO TRIUNFAL</strong><span>Central Web · HQ</span></div>
        </div>
        <div className="loginStatement">
          <span>CENTRAL DE GESTÃO E OPERAÇÕES</span>
          <h1>Uma empresa.<br />Uma identidade.<br />Várias plataformas.</h1>
          <p>Acesso corporativo seguro para as equipas da DeliGo Triunfal, Lda.</p>
        </div>
        <div className="loginPlatforms">
          {["DeliGo", "Comunhão", "TaoMoz", "SARCA"].map((item) => <span key={item}>{item}</span>)}
        </div>
        <small>Exclusivo para trabalhadores e colaboradores autorizados.</small>
      </section>

      <section className="loginFormPanel">
        <div className="loginMobileBrand">
          <img src="/deligo-icon.png" alt="" /><strong>DeliGo Triunfal HQ</strong>
        </div>
        <form className="loginCard" onSubmit={submit}>
          <div className="loginHeading">
            <span>ACESSO CORPORATIVO</span>
            <h2>Bem-vindo de volta</h2>
            <p>Entre com os dados atribuídos pela DeliGo Triunfal.</p>
          </div>
          <label className="loginField">
            <span>Email corporativo</span>
            <div className="phoneInput"><b>@</b><input name="email" type="email" placeholder="nome@staging.deligo.co.mz" autoComplete="username" required /></div>
          </label>
          <label className="loginField">
            <span>Palavra-passe</span>
            <div className="passwordInput"><input name="password" type={showPassword ? "text" : "password"} placeholder="Introduza a sua palavra-passe" autoComplete="current-password" required /><button type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Ocultar" : "Mostrar"}</button></div>
          </label>
          <div className="loginOptions">
            <label><input type="checkbox" /> <span>Confiar neste dispositivo</span></label>
            <button type="button">Esqueceu a palavra-passe?</button>
          </div>
          <button className="loginSubmit" type="submit" disabled={loading}>{loading ? "A validar…" : "Entrar"} <span>→</span></button>
          {notice && <div className="loginNotice"><b>Acesso não autorizado</b><span>{notice}</span></div>}
          <div className="loginSecurity"><i>♧</i><div><strong>Protecção em duas etapas</strong><span>Após a palavra-passe, cargos protegidos confirmarão o acesso com Authenticator ou OTP.</span></div></div>
          <p className="noSignup">Não possui conta? Contacte Recursos Humanos ou a Administração.</p>
        </form>
        <footer className="loginFooter"><span>© 2026 DeliGo Triunfal, Lda.</span><span>Privacidade · Segurança · Suporte interno</span></footer>
      </section>
    </main>
  );
}
