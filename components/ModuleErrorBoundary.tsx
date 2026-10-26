"use client";

import { Component, type ErrorInfo, type ReactNode } from "react";

type Props = { resetKey: string; children: ReactNode };
type State = { error: Error | null; key: string };

/** Keeps the authenticated shell usable when one module receives a malformed payload. */
export class ModuleErrorBoundary extends Component<Props, State> {
  state: State = { error: null, key: this.props.resetKey };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  static getDerivedStateFromProps(props: Props, state: State): Partial<State> | null {
    return props.resetKey !== state.key ? { error: null, key: props.resetKey } : null;
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Central module render failure", error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <section className="moduleRuntimeError" role="alert">
        <span>MÓDULO</span>
        <h2>Não foi possível apresentar esta tela</h2>
        <p>A sessão continua activa. Actualize apenas este módulo para tentar novamente.</p>
        <button type="button" onClick={() => this.setState({ error: null, key: this.props.resetKey })}>
          Tentar novamente
        </button>
      </section>
    );
  }
}
