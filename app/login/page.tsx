"use client";

import { FormEvent, useState } from "react";

export default function LoginPage() {
  const [showPassword, setShowPassword] = useState(false);
  const [notice, setNotice] = useState(false);

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setNotice(true);
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
            <span>Número de telefone</span>
            <div className="phoneInput"><b>+258</b><input type="tel" inputMode="tel" placeholder="84 000 0000" autoComplete="tel" required /></div>
          </label>
          <label className="loginField">
            <span>Palavra-passe</span>
            <div className="passwordInput"><input type={showPassword ? "text" : "password"} placeholder="Introduza a sua palavra-passe" autoComplete="current-password" required /><button type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Ocultar" : "Mostrar"}</button></div>
          </label>
          <div className="loginOptions">
            <label><input type="checkbox" /> <span>Confiar neste dispositivo</span></label>
            <button type="button">Esqueceu a palavra-passe?</button>
          </div>
          <button className="loginSubmit" type="submit">Entrar <span>→</span></button>
          {notice && <div className="loginNotice"><b>Autenticação ainda não ligada</b><span>Este ecrã está preparado, mas nenhuma credencial foi enviada ou guardada. A ligação será feita apenas depois da aprovação do backend.</span></div>}
          <div className="loginSecurity"><i>♧</i><div><strong>Protecção em duas etapas</strong><span>Após a palavra-passe, cargos protegidos confirmarão o acesso com Authenticator ou OTP.</span></div></div>
          <p className="noSignup">Não possui conta? Contacte Recursos Humanos ou a Administração.</p>
        </form>
        <footer className="loginFooter"><span>© 2026 DeliGo Triunfal, Lda.</span><span>Privacidade · Segurança · Suporte interno</span></footer>
      </section>
    </main>
  );
}
