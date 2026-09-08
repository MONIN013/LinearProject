"""Independent numerical checks of MATLAB equations, NOT MATLAB execution.

Run: python tests/verify_acceleration_math.py
Requires NumPy. No network, driver, or hardware access. Success does not
validate MATLAB syntax, Simulink, ADS, monitoring or safety behavior.
"""
import unittest
import numpy as np


def forward(distance, duration, warp, dt):
    duration = np.ceil(duration / dt) * dt
    s = np.arange(round(duration / dt) + 1) * dt / duration
    u = s + warp * (s*s - 2*s**3 + s**4)
    u1 = 1 + warp * (2*s - 6*s*s + 4*s**3)
    u2 = warp * (2 - 12*s + 12*s*s)
    u3 = warp * (-12 + 24*s)
    h = 10*u**3 - 15*u**4 + 6*u**5
    h1 = 30*u*u - 60*u**3 + 30*u**4
    h2 = 60*u - 180*u*u + 120*u**3
    h3 = 60 - 360*u + 360*u*u
    return np.column_stack((distance*h, distance*h1*u1/duration,
        distance*(h2*u1*u1+h1*u2)/duration**2,
        distance*(h3*u1**3+3*h2*u1*u2+h1*u3)/duration**3))


class Equations(unittest.TestCase):
    def test_endpoints_and_monotonicity(self):
        for warp in (-1, -.65, 0, .65, 1):
            z = forward(.84, 6, warp, .001)
            np.testing.assert_allclose(z[[0, -1], :3], [[0, 0, 0], [.84, 0, 0]], atol=1e-12)
            self.assertTrue(np.all(np.diff(z[:, 0]) > 0))

    def test_analytic_derivatives(self):
        z = forward(.84, 6, .65, .001)
        for order in range(3):
            numeric = (z[2:, order] - z[:-2, order]) / .002
            np.testing.assert_allclose(numeric, z[1:-1, order+1], atol=1e-6)

    def test_time_reversal_acceleration_is_even(self):
        z = forward(.84, 6, .65, .001)
        back = z[::-1] * [1, -1, 1, -1]
        np.testing.assert_allclose(back[:, 2], z[::-1, 2])
        np.testing.assert_allclose(back[:, 1], -z[::-1, 1])

    def test_scaled_least_squares_recovers_four_coefficients(self):
        v = np.array([.1, -.1, .2, -.2, .3, -.3])
        a = np.array([.1, .1, -.2, -.2, .3, .3])
        x = np.column_stack((np.ones(6), v, np.sign(v), a))
        beta = np.array([.05, .2, .05, .3])
        scale = np.sqrt(np.mean(x*x, axis=0))
        estimated = np.linalg.lstsq(x/scale, x@beta, rcond=None)[0]/scale
        np.testing.assert_allclose(estimated, beta, atol=1e-12)
        self.assertEqual(np.linalg.matrix_rank(x/scale), 4)

    def test_acceleration_confounding_is_detected(self):
        v = np.array([.1, -.1, .2, -.2, .3, -.3])
        x = np.column_stack((np.ones(6), v, np.sign(v), 2*v))
        self.assertLess(np.linalg.matrix_rank(x), 4)
        residual = x[:, 3] - x[:, :3] @ np.linalg.lstsq(x[:, :3], x[:, 3], rcond=None)[0]
        self.assertLess(residual@residual/(x[:, 3]@x[:, 3]), 1e-20)

    def test_local_cubic_measured_differentiation(self):
        dt=.00025; half=20
        s=np.arange(-half, half+1)/half
        w=np.linalg.pinv(np.column_stack((np.ones(len(s)), s, s*s, s**3)))
        t=np.arange(200)*dt
        y=5.41+.1*t+.2*t*t+.3*t**3
        v=np.convolve(y,w[1, ::-1],mode='valid')/(half*dt)
        a=2*np.convolve(y,w[2, ::-1],mode='valid')/(half*dt)**2
        c=t[half:-half]
        np.testing.assert_allclose(v,.1+.4*c+.9*c*c,atol=1e-10)
        np.testing.assert_allclose(a,.4+1.8*c,atol=1e-8)

    def test_one_sample_logging_delay_is_not_circular(self):
        x=np.arange(5)
        logged=np.r_[0, x[:-1]]
        np.testing.assert_array_equal(logged,[0,0,1,2,3])
        self.assertNotEqual(logged[0],x[-1])

    def test_feedforward_advance_is_applied_once(self):
        raw=np.array([0.,.1,.2,.3,0.]); advance=2
        np.testing.assert_array_equal(np.r_[raw[advance:],np.repeat(raw[-1],advance)], [.2,.3,0,0,0])

    def test_candidate_profile_excitation_has_interior_rank(self):
        profiles=[forward(.84, T, w, .001) for T in (6,8,10) for w in (-.65,.65)]
        for position in (.1,.2,.4,.6,.7):
            rows=[]
            for p in profiles:
                v=np.interp(position,p[:,0],p[:,1]); a=np.interp(position,p[:,0],p[:,2])
                rows.extend(([1,v,1,a],[1,-v,-1,a]))
            x=np.array(rows); z=x/np.sqrt(np.mean(x*x,axis=0))
            self.assertEqual(np.linalg.matrix_rank(z),4)
            self.assertLess(np.linalg.cond(z),1000)


if __name__ == '__main__':
    unittest.main(verbosity=2)
