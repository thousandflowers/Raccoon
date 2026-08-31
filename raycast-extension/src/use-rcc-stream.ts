import { useCallback, useEffect, useRef, useState } from "react";
import { streamRcc } from "./rcc";

/**
 * Run `rcc <args>` and expose its output as it arrives.
 *
 * Long commands (`upgrade`, `audit --deep`) print progress for minutes, so the
 * view fills in live instead of sitting empty behind a spinner.
 */
export function useRccStream(args: string[]) {
	const [output, setOutput] = useState("");
	const [isLoading, setIsLoading] = useState(true);
	const [error, setError] = useState<Error | undefined>();
	const [runCount, setRunCount] = useState(0);
	const controllerRef = useRef<AbortController>(undefined);

	const key = args.join(" ");

	useEffect(() => {
		const controller = new AbortController();
		controllerRef.current = controller;
		setOutput("");
		setError(undefined);
		setIsLoading(true);

		streamRcc(
			key.split(" "),
			(chunk) => setOutput((previous) => previous + chunk),
			controller.signal,
		)
			.catch((caught: Error) => setError(caught))
			.finally(() => setIsLoading(false));

		return () => controller.abort();
	}, [key, runCount]);

	const reload = useCallback(() => setRunCount((n) => n + 1), []);
	const stop = useCallback(() => controllerRef.current?.abort(), []);

	return { output, isLoading, error, reload, stop };
}
