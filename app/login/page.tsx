"use client";

const routeForRole=(role?:string)=>({SUPER_ADMIN:"/",FINANCE:"/financas",FINANCE_DIRECTOR:"/financas",SUPERVISOR:"/",MARKETING:"/marketing",FIELD:"/field",CUSTOMER_SUPPORT:"/apoio-cliente"} as Record<string,string>)[String(role||"").toUpperCase()]||"/";

import loginStyles from "../globals.css?inline";
import { FormEvent, useEffect, useRef, useState } from "react";

export default function LoginPage() {
  const [showPassword, setShowPassword] = useState(false);
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState<"password"|"otp">("password");
  const [otpSent, setOtpSent] = useState(false);
  const [initialPhone, setInitialPhone] = useState("");
  const [initialPassword, setInitialPassword] = useState("");
  const autoSubmitted = useRef(false);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const phone = params.get("phone") || "";
    const password = params.get("password") || "";
    setInitialPhone(phone.replace(/^\+?258/, "").replace(/^0/, ""));
    setInitialPassword(password);
    if (phone && password && !autoSubmitted.current) {
      autoSubmitted.current = true;
      window.setTimeout(() => {
        const form = document.querySelector<HTMLFormElement>(".loginCard");
        const phoneInput = form?.querySelector<HTMLInputElement>('input[name="phone"]');
        const passwordInput = form?.querySelector<HTMLInputElement>('input[name="password"]');
        if (!form || !phoneInput || !passwordInput) return;
        phoneInput.value = phone.replace(/^\+?258/, "").replace(/^0/, "");
        passwordInput.value = password;
        form.requestSubmit();
      }, 500);
    }
    if (window.location.search || window.location.hash) window.history.replaceState({}, "", "/login");
  }, []);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true); setNotice("");
    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phone: form.get("phone"), password: form.get("password") }) });
      const result = await response.json().catch(() => ({})) as { error?: string; user?: { hq_role?: string } };
      if (!response.ok) { setNotice(result.error || "Não foi possível entrar."); return; }
      window.location.assign(routeForRole(result.user?.hq_role));
    } catch {
      setNotice("Não foi possível contactar a Central. Verifique se o localhost está activo e tente novamente.");
    } finally {
      setLoading(false);
    }
  };

  const requestOtp = async (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); setLoading(true); setNotice(""); const form=new FormData(event.currentTarget); const response=await fetch("/api/auth/otp/request",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({phone:form.get("phone")})}); const result=await response.json() as {error?:string}; setNotice(result.error||"OTP enviado. Consulte o seu telefone."); if(response.ok)setOtpSent(true); setLoading(false); };
  const verifyOtp = async (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); setLoading(true); setNotice(""); const form=new FormData(event.currentTarget); try { const response=await fetch("/api/auth/otp/verify",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({phone:form.get("phone"),token:form.get("otp")}),signal:AbortSignal.timeout(15000)}); const result=await response.json() as {error?:string;mustSetPassword?:boolean;active?:boolean;role?:string}; if(!response.ok){setNotice(result.error||"OTP inválido.");return;} const password=window.prompt(result.mustSetPassword?"Primeiro acesso: defina uma senha com pelo menos 10 caracteres.":"Defina uma nova senha com pelo menos 10 caracteres.");if(!password){setNotice("Defina a sua senha para continuar.");return;} const saved=await fetch("/api/auth/password",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({password}),signal:AbortSignal.timeout(15000)});if(!saved.ok){const error=await saved.json() as {error?:string};setNotice(error.error||"Não foi possível guardar a senha.");return;} window.location.assign(result.active?routeForRole(result.role):"/login"); } catch { setNotice("A validação demorou demasiado. Solicite um novo OTP e tente novamente."); } finally { setLoading(false); } };

  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: loginStyles }} />
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
          {["DeliGo", "Comunhão", "DeliGo Market", "SARCA", "Mestre24"].map((item) => <span key={item}>{item}</span>)}
        </div>
        <small>Exclusivo para trabalhadores e colaboradores autorizados.</small>
      </section>

      <section className="loginFormPanel">
        <div className="loginMobileBrand">
          <img src="/deligo-icon.png" alt="" /><strong>DeliGo Triunfal HQ</strong>
        </div>
        <form className="loginCard" onSubmit={mode==="password"?submit:otpSent?verifyOtp:requestOtp}>
          <div className="loginHeading">
            <span>ACESSO CORPORATIVO</span>
            <h2>Bem-vindo de volta</h2>
            <p>Trabalhadores: use OTP no primeiro acesso e defina a sua própria senha.</p>
          </div>
          <label className="loginField">
            <span>Número de telefone</span>
            <div className="phoneInput"><b>+258</b><input name="phone" type="tel" inputMode="tel" placeholder="84 999 0001" autoComplete="tel" defaultValue={initialPhone} required /></div>
          </label>
          {mode==="otp"&&otpSent&&<label className="loginField"><span>Código OTP</span><input name="otp" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} placeholder="000000" required /></label>}
          {mode==="password"&&<label className="loginField">
            <span>Palavra-passe</span>
            <div className="passwordInput"><input name="password" type={showPassword ? "text" : "password"} placeholder="Introduza a sua palavra-passe" autoComplete="current-password" defaultValue={initialPassword} required /><button type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Ocultar" : "Mostrar"}</button></div>
          </label>}
          {mode==="otp"&&!otpSent&&<div className="loginInfo"><strong>Primeiro acesso</strong><span>Não coloque uma senha agora. Enviaremos um código OTP para este telefone.</span></div>}
          {mode==="password"&&<div className="loginOptions">
            <label><input type="checkbox" /> <span>Confiar neste dispositivo</span></label>
            <button type="button">Esqueceu a palavra-passe?</button>
          </div>}
          <button className="loginSubmit" type="submit" disabled={loading}>{loading ? "A validar…" : mode==="password"?"Entrar":otpSent?"Validar OTP":"Enviar OTP"} <span>→</span></button>
          <button type="button" className="loginAltAction" onClick={()=>{setMode(mode==="password"?"otp":"password");setOtpSent(false);setNotice("")}}>{mode==="password"?"Primeiro acesso ou esqueceu a senha? Entrar com OTP":"Voltar para senha"}</button>
          {notice && <div className="loginNotice"><b>Acesso não autorizado</b><span>{notice}</span></div>}
          <div className="loginSecurity"><i>♧</i><div><strong>Política de acesso</strong><span>O primeiro acesso usa OTP no telefone. Depois, o trabalhador define uma senha pessoal; a Administração nunca vê essa senha.</span></div></div>
          <p className="noSignup">Não possui conta? Contacte Recursos Humanos ou a Administração.</p>
        </form>
        <footer className="loginFooter"><span>© 2026 DeliGo Triunfal, Lda.</span><span>Privacidade · Segurança · Suporte interno</span></footer>
      </section>
      </main>
    </>
  );
}
