export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return <div className="analyticsErrorState" role="alert"><strong>Não foi possível carregar os dados</strong><span>{message}</span>{onRetry && <button type="button" onClick={onRetry}>Tentar novamente</button>}</div>;
}
