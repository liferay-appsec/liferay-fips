package com.liferay.fips.tomcat;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.net.URL;
import java.security.ProtectionDomain;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Clears the global {@link URLStreamHandlerFactory} just before Equinox tries
 * to install its own implementation so the registration succeeds even if
 * Tomcat already registered a factory earlier.
 */
public class TomcatUrlHandlerDisabler {

	public static void premain(String agentArgs, Instrumentation instrumentation) {
		_installTransformer(instrumentation);
	}

	public static void premain(String agentArgs) {
		_installTransformer(null);
	}

	public static void agentmain(String agentArgs, Instrumentation instrumentation) {
		_installTransformer(instrumentation);
	}

	public static void agentmain(String agentArgs) {
		_installTransformer(null);
	}

	private static void _installTransformer(Instrumentation instrumentation) {
		if ((instrumentation == null) || _transformerInstalled.getAndSet(true)) {
			return;
		}

		instrumentation.addTransformer(new EquinoxTriggerTransformer());
	}

	private static void _resetURLFactory() {
		try {
			Field factoryField = URL.class.getDeclaredField("factory");
			Field factorySetField = URL.class.getDeclaredField("factorySet");

			factoryField.setAccessible(true);
			factorySetField.setAccessible(true);

			Object existingFactory = factoryField.get(null);

			if (existingFactory == null) {
				return;
			}

			factoryField.set(null, null);
			factorySetField.setBoolean(null, false);

			System.err.println(
				"[tomcat-url-handler-disabler] Cleared pre-existing URLStreamHandlerFactory: " +
					existingFactory.getClass().getName());
		}
		catch (ReflectiveOperationException exception) {
			throw new IllegalStateException(
				"Unable to reset java.net.URL factory", exception);
		}
	}

	private static class EquinoxTriggerTransformer implements ClassFileTransformer {

		@Override
		public byte[] transform(
			ClassLoader loader, String className, Class<?> classBeingRedefined,
			ProtectionDomain protectionDomain, byte[] classfileBuffer) {

			if (!_factoryCleared.get() &&
				"org/eclipse/osgi/internal/url/EquinoxFactoryManager".equals(
					className)) {

				_factoryCleared.set(true);
				_resetURLFactory();
			}

			return null;
		}

	}

	private static final AtomicBoolean _factoryCleared = new AtomicBoolean();
	private static final AtomicBoolean _transformerInstalled =
		new AtomicBoolean();

}
